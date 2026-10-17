package com.carriez.flutter_hbb

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
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
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * UnattendedAccessService — foreground service that runs persistently so
 * operators can connect to this device at any time.
 *
 * Responsibilities:
 *   • Keeps the BetterDesk client alive in the background (starts on boot).
 *   • Hosts the incoming connection listener for operator remote control.
 *   • Manages the permanent unattended-access password.
 *   • Exposes a method channel to the Flutter UI for configuration.
 */
class UnattendedAccessService : Service() {

    companion object {
        const val TAG = "UnattendedAccessService"
        const val CHANNEL_ID = "betterdesk.unattended"
        const val NOTIFICATION_ID = 1001

        /** Latest JPEG frame captured from MediaProjection (screen share). */
        @Volatile
        var latestFrame: ByteArray? = null
            private set

        private var virtualDisplay: VirtualDisplay? = null
        private var imageReader: ImageReader? = null

        /**
         * Called once, from MainActivity's "Allow once" MediaProjection grant.
         * Holds the projection, starts a VirtualDisplay + ImageReader capture
         * pipeline, and starts the foreground service so the projection
         * outlives the UI. The device owner is never prompted again while the
         * service runs (Android itself only allows one system prompt; the
         * grant is held here for the session).
         */
        fun attachProjection(projection: MediaProjection?, context: Context) {
            val proj = projection ?: return
            MainActivity.mediaProjection = proj
            val metrics = context.resources.displayMetrics
            val width = metrics.widthPixels
            val height = metrics.heightPixels
            val dpi = metrics.densityDpi
            val handler = Handler(Looper.getMainLooper())

            // Android 14+ requires a registered callback before use.
            proj.registerCallback(object : MediaProjection.Callback() {}, handler)

            val reader = ImageReader.newInstance(width, height, 256, 2) // ImageFormat.JPEG
            reader.setOnImageAvailableListener({ r ->
                try {
                    val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                    val plane = image.planes[0]
                    val buf = plane.buffer
                    val bytes = ByteArray(buf.remaining())
                    buf.get(bytes)
                    image.close()
                    latestFrame = bytes
                } catch (e: Exception) {
                    Log.w(TAG, "frame capture error: ${e.message}")
                }
            }, handler)

            virtualDisplay = proj.createVirtualDisplay(
                "BetterDeskCapture", width, height, dpi,
                android.hardware.display.DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, handler
            )
            imageReader = reader
            Log.i(TAG, "Screen capture attached ${width}x${height} @ ${dpi}dpi")

            val intent = Intent(context, UnattendedAccessService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    private lateinit var flutterEngine: FlutterEngine

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "UnattendedAccessService onCreate")

        // Initialize a headless Flutter engine so the app can run UI-less
        // while still being able to render the configuration UI on demand.
        flutterEngine = FlutterEngine(this)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )

        // Start the incoming-connection listener via the method channel.
        UnattendedAccessManager.init(flutterEngine.dartExecutor.binaryMessenger, this)
        IncomingConnectionManager.start(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "UnattendedAccessService onStartCommand")
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "UnattendedAccessService onDestroy")
        IncomingConnectionManager.stop()
        UnattendedAccessManager.dispose()
        super.onDestroy()
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

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("BetterDesk Unattended Access")
            .setContentText("Remote control enabled — device is accepting incoming connections")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}
