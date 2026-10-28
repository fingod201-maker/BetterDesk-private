package com.carriez.flutter_hbb

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import java.io.ByteArrayOutputStream

/**
 * UnattendedAccessService — foreground service that runs persistently so
 * operators can connect to this device at any time.
 *
 * Responsibilities:
 *   • Keeps the BetterDesk client alive in the background (starts on boot).
 *   • Hosts the incoming connection listener for operator remote control.
 *   • Manages the permanent unattended-access password.
 *   • Holds the MediaProjection screen-capture grant for the session.
 *
 * Android 14+ (API 34) requirements implemented here:
 *   • The service is a foreground service of type `mediaProjection` *before*
 *     MediaProjectionManager.getMediaProjection() is called. Calling it first
 *     throws SecurityException and kills the process.
 *   • Screen frames are captured as RGBA_8888 (VirtualDisplay cannot render
 *     into a JPEG ImageReader) and compressed to JPEG in-process.
 *   • The projection consent token cannot be persisted by Android, so after a
 *     reboot/process death the user is prompted once via a notification to
 *     re-authorize the session.
 */
class UnattendedAccessService : Service() {

    interface ProjectionResultCallback {
        fun onProjectionResult(success: Boolean, message: String?)
    }

    companion object {
        const val TAG = "UnattendedAccessService"
        // Versioned id: Android refuses to *lower* the importance of a channel
        // that already exists, so upgrades from builds that shipped
        // IMPORTANCE_LOW would keep an audible/loud notification forever.
        // A brand-new id on upgrade guarantees the quiet channel applies.
        const val CHANNEL_ID = "betterdesk.unattended.v2"
        const val LEGACY_CHANNEL_ID = "betterdesk.unattended"
        const val ALERT_CHANNEL_ID = "betterdesk.alerts"
        const val NOTIFICATION_ID = 1001
        const val REGRANT_NOTIFICATION_ID = 1002

        const val ACTION_START_PROJECTION = "com.betterdesk.action.START_PROJECTION"
        const val EXTRA_RESULT_CODE = "screen_capture_result_code"
        const val EXTRA_RESULT_DATA = "screen_capture_result_data"

        private const val PREFS_NAME = "betterdesk_unattended"
        private const val KEY_CAPTURE_GRANTED_ONCE = "screen_capture_was_granted"

        @Volatile
        private var runningFlag = false

        @JvmStatic
        fun isRunning(): Boolean = runningFlag

        /** Latest JPEG frame captured from MediaProjection (screen share). */
        @Volatile
        var latestFrame: ByteArray? = null
            private set

        @Volatile
        private var projectionActive = false

        @Volatile
        private var pendingProjectionCallback: ProjectionResultCallback? = null

        fun isProjectionActive(): Boolean = projectionActive

        /**
         * Called from MainActivity's "Allow once" MediaProjection grant.
         *
         * The consent result is handed to the service instead of calling
         * getMediaProjection() in the activity: on Android 14+ the app must
         * already be running a mediaProjection-type foreground service before
         * that call is allowed.
         */
        fun startProjection(
            context: Context,
            resultCode: Int,
            data: Intent,
            callback: ProjectionResultCallback,
        ) {
            pendingProjectionCallback = callback
            val intent = Intent(context, UnattendedAccessService::class.java).apply {
                action = ACTION_START_PROJECTION
                putExtra(EXTRA_RESULT_CODE, resultCode)
                putExtra(EXTRA_RESULT_DATA, data)
            }
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (t: Throwable) {
                pendingProjectionCallback = null
                callback.onProjectionResult(
                    false,
                    t.message ?: "Unable to start the screen capture service"
                )
            }
        }
    }

    private var flutterEngine: FlutterEngine? = null
    private var projection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Throttle screen capture so we never starve the device with JPEG encodes. */
    @Volatile
    private var lastFrameAt = 0L
    private val frameIntervalMs = 200L

    /** Downscale very large displays before JPEG encoding (memory/ANR guard). */
    private val maxCaptureDimension = 1600

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "UnattendedAccessService onCreate")
        runningFlag = true
        CrashLogger.install(this)
        RemoteControlAccessibilityService.attachContext(this)

        // Initialize a headless Flutter engine so the app can run UI-less
        // while still being able to render the configuration UI on demand.
        flutterEngine = FlutterEngine(this).apply {
            dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            UnattendedAccessManager.init(dartExecutor.binaryMessenger, this@UnattendedAccessService)
        }

        IncomingConnectionManager.start(this)
        AgentRelayBridge.start(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "UnattendedAccessService onStartCommand action=${intent?.action}")
        CrashLogger.install(this)

        try {
            if (intent?.action == ACTION_START_PROJECTION) {
                // Must be a mediaProjection FGS before getMediaProjection() on API 34+.
                val foregroundStarted = startAsForeground(includeMediaProjection = true)
                if (foregroundStarted) {
                    handleProjectionConsent(intent)
                } else {
                    failPendingProjection(
                        "Foreground service could not start for screen capture"
                    )
                    promptForRegrantIfNeeded()
                }
            } else {
                startAsForeground(includeMediaProjection = projection != null)
                // Idempotent: re-arms the enrollment/relay dialer if a previous
                // attempt failed, so the Flutter retry button works without a
                // process restart.
                AgentRelayBridge.start(this)
                promptForRegrantIfNeeded()
                scheduleAutoRegrant()
            }
        } catch (t: Throwable) {
            // Never let a foreground-service failure kill the process — that
            // shows up to the user as the app simply "closing".
            Log.e(TAG, "onStartCommand failed: ${t.javaClass.simpleName}", t)
            failPendingProjection(t.message ?: t.javaClass.simpleName)
        }
        return START_STICKY
    }

    private fun failPendingProjection(message: String) {
        val callback = pendingProjectionCallback
        pendingProjectionCallback = null
        callback?.onProjectionResult(false, message)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "UnattendedAccessService onDestroy")
        runningFlag = false
        releaseProjection(stop = true)
        cancelRegrantNotification()
        IncomingConnectionManager.stop()
        AgentRelayBridge.stop()
        UnattendedAccessManager.dispose()
        flutterEngine?.destroy()
        flutterEngine = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Throwable) {}
        } else {
            @Suppress("DEPRECATION")
            try { stopForeground(true) } catch (_: Throwable) {}
        }
        super.onDestroy()
    }

    // ---- Foreground service ----

    /**
     * Promote the service to the foreground.
     *
     * Returns true when the notification is posted. On API 34+ starting a
     * `mediaProjection` FGS can throw [android.app.ForegroundServiceStartNotAllowedException]
     * or a [SecurityException] on OEM builds; we degrade to a plain
     * `connectedDevice` service instead of crashing.
     */
    private fun startAsForeground(includeMediaProjection: Boolean): Boolean {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            if (includeMediaProjection) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            }
            try {
                startForeground(NOTIFICATION_ID, notification, type)
                return true
            } catch (t: Throwable) {
                Log.e(
                    TAG,
                    "startForeground(type=$type) failed: ${t.javaClass.simpleName}: ${t.message}",
                    t
                )
                if (includeMediaProjection) {
                    try {
                        startForeground(
                            NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                        )
                        return true
                    } catch (t2: Throwable) {
                        Log.e(TAG, "Fallback startForeground failed", t2)
                    }
                }
            }
            return false
        }
        startForeground(NOTIFICATION_ID, notification)
        return true
    }

    // ---- MediaProjection ----

    private fun handleProjectionConsent(intent: Intent) {
        val callback = pendingProjectionCallback
        pendingProjectionCallback = null

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
        val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }

        if (resultCode != Activity.RESULT_OK || data == null) {
            startAsForeground(includeMediaProjection = false)
            callback?.onProjectionResult(false, "Screen capture permission was not granted")
            return
        }

        try {
            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val proj = mpm.getMediaProjection(resultCode, data)
                ?: throw IllegalStateException("MediaProjectionManager returned null")
            attachProjection(proj)
            callback?.onProjectionResult(true, null)
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to attach MediaProjection", t)
            startAsForeground(includeMediaProjection = false)
            callback?.onProjectionResult(false, t.message ?: t.javaClass.simpleName)
        }
    }

    private fun attachProjection(proj: MediaProjection) {
        releaseProjection(stop = true)

        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val dpi = metrics.densityDpi

        projection = proj
        MainActivity.mediaProjection = proj

        // Android 14+ requires a registered callback before use.
        proj.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.i(TAG, "MediaProjection stopped by the system or user")
                mainHandler.post {
                    // Ignore a stop callback from a projection we already
                    // replaced with a newer consent grant.
                    if (projection === proj) {
                        releaseProjection(stop = false)
                        promptForRegrantIfNeeded()
                    }
                }
            }
        }, mainHandler)

        // Screen capture must use an uncompressed producer format; RGBA_8888
        // is the only reliable format for a VirtualDisplay surface.
        val captureHandler = ensureCaptureThread()
        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        reader.setOnImageAvailableListener({ r ->
            try {
                val now = System.currentTimeMillis()
                // ALWAYS acquire and close the latest image, even while
                // throttled or idle. Returning before acquireLatestImage()
                // lets the ImageReader's buffer queue (maxImages = 2) fill; the
                // VirtualDisplay producer then blocks, onImageAvailable stops
                // firing, and capture stays dead for every later viewer (black
                // screen) until a brand-new projection is created.
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    if (now - lastFrameAt < frameIntervalMs) {
                        // Drop this frame; acquireLatestImage() already
                        // discarded any still-buffered frames.
                        return@setOnImageAvailableListener
                    }
                    if (!AgentRelayBridge.streaming()) {
                        // No operator session live over the relay: keep the
                        // projection warm but skip the expensive JPEG encode.
                        lastFrameAt = now
                        return@setOnImageAvailableListener
                    }
                    val plane = image.planes[0]
                    val buffer = plane.buffer
                    buffer.rewind()

                    val pixelStride = plane.pixelStride
                    val rowStride = plane.rowStride
                    val rowPadding = rowStride - pixelStride * width
                    val paddedWidth = width + rowPadding / pixelStride

                    val padded = Bitmap.createBitmap(
                        paddedWidth, height, Bitmap.Config.ARGB_8888
                    )
                    padded.copyPixelsFromBuffer(buffer)
                    val cropped = if (paddedWidth == width) {
                        padded
                    } else {
                        Bitmap.createBitmap(padded, 0, 0, width, height)
                    }

                    val longest = maxOf(cropped.width, cropped.height)
                    val frame = if (longest > maxCaptureDimension) {
                        val scale = maxCaptureDimension.toFloat() / longest
                        Bitmap.createScaledBitmap(
                            cropped,
                            (cropped.width * scale).toInt().coerceAtLeast(1),
                            (cropped.height * scale).toInt().coerceAtLeast(1),
                            true
                        )
                    } else {
                        cropped
                    }

                    val out = ByteArrayOutputStream()
                    frame.compress(Bitmap.CompressFormat.JPEG, 70, out)
                    latestFrame = out.toByteArray()
                    AgentRelayBridge.noteCaptureSize(frame.width, frame.height)
                    AgentRelayBridge.feed(out.toByteArray())
                    lastFrameAt = now

                    if (frame !== cropped) frame.recycle()
                    if (cropped !== padded) cropped.recycle()
                    padded.recycle()
                } finally {
                    image.close()
                }
            } catch (e: Exception) {
                Log.w(TAG, "frame capture error: ${e.message}")
            }
        }, captureHandler)

        virtualDisplay = proj.createVirtualDisplay(
            "BetterDeskCapture", width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, captureHandler
        )
        imageReader = reader
        projectionActive = true

        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_CAPTURE_GRANTED_ONCE, true)
            .apply()
        cancelRegrantNotification()

        Log.i(TAG, "Screen capture attached ${width}x${height} @ ${dpi}dpi")
    }

    private fun releaseProjection(stop: Boolean) {
        imageReader?.setOnImageAvailableListener(null, null)
        try { imageReader?.close() } catch (_: Exception) {}
        imageReader = null

        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null

        val current = projection
        projection = null
        if (stop && current != null) {
            try { current.stop() } catch (_: Exception) {}
        }

        captureThread?.quitSafely()
        captureThread = null

        lastFrameAt = 0L
        projectionActive = false
        latestFrame = null
        MainActivity.mediaProjection = null
    }

    private fun ensureCaptureThread(): Handler {
        var thread = captureThread
        if (thread == null || !thread.isAlive) {
            thread = HandlerThread("BetterDeskCapture").also {
                it.start()
                captureThread = it
            }
        }
        return Handler(thread.looper)
    }

    // ---- Re-grant reminder (Android cannot persist the projection token) ----

    /**
     * After a reboot/process death Android drops the MediaProjection token, so
     * the service proactively re-acquires it: it launches the translucent
     * [ProjectionRegrantActivity] and the accessibility service accepts the
     * system "Start now" dialog — the device comes back fully streamable with no
     * user interaction. The accessibility still-image path covers the gap while
     * this runs (and if it is ever blocked).
     */
    private fun scheduleAutoRegrant() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return
        if (projection != null) return
        if (!captureGrantedBefore()) return
        // Give the system a moment to settle after boot, and retry a couple of
        // times in case the first attempt races the lock screen or the
        // accessibility service reconnect.
        for (delay in longArrayOf(10_000L, 45_000L, 150_000L)) {
            mainHandler.postDelayed({
                if (projection == null && captureGrantedBefore()) launchRegrantActivity()
            }, delay)
        }
    }

    private fun captureGrantedBefore(): Boolean =
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getBoolean(KEY_CAPTURE_GRANTED_ONCE, false)

    private fun launchRegrantActivity() {
        try {
            RemoteControlAccessibilityService.attachContext(this)
            val intent = Intent(this, ProjectionRegrantActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            }
            startActivity(intent)
            Log.i(TAG, "auto-regrant: launched projection consent activity")
        } catch (t: Throwable) {
            Log.w(TAG, "auto-regrant launch failed: ${t.message}")
            promptForRegrantIfNeeded()
        }
    }

    private fun promptForRegrantIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return
        if (projection != null) return
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_CAPTURE_GRANTED_ONCE, false)) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val manager = NotificationManagerCompat.from(this)
        if (!manager.areNotificationsEnabled()) return

        ensureAlertChannel()

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("betterdesk_regrant_screen_capture", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 1, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("Screen sharing needs re-approval")
            .setContentText("Android resets screen-capture consent after a restart. Tap to allow sharing again.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        try {
            manager.notify(REGRANT_NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Cannot post re-grant notification: ${e.message}")
        }
    }

    private fun cancelRegrantNotification() {
        try {
            NotificationManagerCompat.from(this).cancel(REGRANT_NOTIFICATION_ID)
        } catch (_: Exception) {}
    }

    private fun ensureAlertChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(ALERT_CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "Zoom-Vip Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Permission and connectivity alerts"
            }
        )
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // IMPORTANCE_MIN collapses the ongoing notification to the bottom
            // of the shade and makes it fully silent — the least visible a
            // required FGS notification can be. Re-apply every start and clear
            // the legacy loud channel left by older builds.
            try { manager.deleteNotificationChannel(CHANNEL_ID) } catch (_: Exception) {}
            try { manager.deleteNotificationChannel(LEGACY_CHANNEL_ID) } catch (_: Exception) {}
            NotificationChannel(
                CHANNEL_ID,
                "Zoom-Vip Remote Access",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps this device reachable by your operator"
                lockscreenVisibility = Notification.VISIBILITY_SECRET
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
        } else null
        if (channel != null) {
            manager.createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val text = if (projectionActive) {
            "Screen sharing active — this device is reachable by your operator"
        } else {
            "Remote access enabled — this device is reachable by your operator"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Zoom-Vip Remote Access")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .build()
    }
}
