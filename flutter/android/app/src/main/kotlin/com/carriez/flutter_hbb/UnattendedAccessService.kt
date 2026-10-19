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
        const val CHANNEL_ID = "betterdesk.unattended"
        const val ALERT_CHANNEL_ID = "betterdesk.alerts"
        const val NOTIFICATION_ID = 1001
        const val REGRANT_NOTIFICATION_ID = 1002

        const val ACTION_START_PROJECTION = "com.betterdesk.action.START_PROJECTION"
        const val EXTRA_RESULT_CODE = "screen_capture_result_code"
        const val EXTRA_RESULT_DATA = "screen_capture_result_data"

        private const val PREFS_NAME = "betterdesk_unattended"
        private const val KEY_CAPTURE_GRANTED_ONCE = "screen_capture_was_granted"

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
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "UnattendedAccessService onCreate")

        // Initialize a headless Flutter engine so the app can run UI-less
        // while still being able to render the configuration UI on demand.
        flutterEngine = FlutterEngine(this).apply {
            dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            UnattendedAccessManager.init(dartExecutor.binaryMessenger, this@UnattendedAccessService)
        }

        IncomingConnectionManager.start(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "UnattendedAccessService onStartCommand action=${intent?.action}")

        if (intent?.action == ACTION_START_PROJECTION) {
            // Must be a mediaProjection FGS before getMediaProjection() on API 34+.
            startAsForeground(includeMediaProjection = true)
            handleProjectionConsent(intent)
        } else {
            startAsForeground(includeMediaProjection = projection != null)
            promptForRegrantIfNeeded()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "UnattendedAccessService onDestroy")
        releaseProjection(stop = true)
        cancelRegrantNotification()
        IncomingConnectionManager.stop()
        UnattendedAccessManager.dispose()
        flutterEngine?.destroy()
        flutterEngine = null
        super.onDestroy()
    }

    // ---- Foreground service ----

    private fun startAsForeground(includeMediaProjection: Boolean) {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            if (includeMediaProjection) {
                type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
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
        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        reader.setOnImageAvailableListener({ r ->
            try {
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
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
                    val frame = if (paddedWidth == width) {
                        padded
                    } else {
                        Bitmap.createBitmap(padded, 0, 0, width, height)
                    }

                    val out = ByteArrayOutputStream()
                    frame.compress(Bitmap.CompressFormat.JPEG, 70, out)
                    latestFrame = out.toByteArray()

                    if (frame !== padded) frame.recycle()
                    padded.recycle()
                } finally {
                    image.close()
                }
            } catch (e: Exception) {
                Log.w(TAG, "frame capture error: ${e.message}")
            }
        }, mainHandler)

        virtualDisplay = proj.createVirtualDisplay(
            "BetterDeskCapture", width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, mainHandler
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

        projectionActive = false
        latestFrame = null
        MainActivity.mediaProjection = null
    }

    // ---- Re-grant reminder (Android cannot persist the projection token) ----

    private fun promptForRegrantIfNeeded() {
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
            .setPriority(NotificationCompat.PRIORITY_HIGH)
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
                "BetterDesk Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Permission and connectivity alerts"
            }
        )
    }

    private fun buildNotification(): Notification {
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel(
                CHANNEL_ID,
                "BetterDesk Unattended Access",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "BetterDesk unattended remote-access service"
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
        } else null
        if (channel != null) {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val text = if (projectionActive) {
            "Screen sharing active — device is accepting incoming connections"
        } else {
            "Remote control enabled — device is accepting incoming connections"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("BetterDesk Unattended Access")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}
