package com.carriez.flutter_hbb

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
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

    private companion object {
        const val TAG = "UnattendedAccessService"
        const val CHANNEL_ID = "betterdesk.unattended"
        const val NOTIFICATION_ID = 1001
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
