package com.android.shell.ghost;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.widget.Toast;

/** Routes PackageInstaller status and package add/remove events. */
public class PackageInstallReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) return;

        if ("com.android.shell.ghost.INSTALL_RESULT".equals(action)) {
            int status = intent.getIntExtra(
                    android.content.pm.PackageInstaller.EXTRA_STATUS,
                    android.content.pm.PackageInstaller.STATUS_FAILURE);
            String message = intent.getStringExtra(
                    android.content.pm.PackageInstaller.EXTRA_STATUS_MESSAGE);
            PayloadInstaller.onInstallResult(context, status, message, intent);
            return;
        }
        if ("com.android.shell.ghost.UNINSTALL_RESULT".equals(action)) {
            int status = intent.getIntExtra(
                    android.content.pm.PackageInstaller.EXTRA_STATUS,
                    android.content.pm.PackageInstaller.STATUS_FAILURE);
            PayloadInstaller.onUninstallResult(context, status);
            return;
        }

        String data = intent.getDataString();
        if (data == null) return;
        String pkg = data.startsWith("package:")
                ? data.substring("package:".length())
                : data;
        if (!PayloadInstaller.PAYLOAD_PACKAGE.equals(pkg)) return;

        boolean removed = Intent.ACTION_PACKAGE_REMOVED.equals(action)
                && !intent.getBooleanExtra(Intent.EXTRA_REPLACING, false);
        if (removed) {
            if ("install".equals(PayloadInstaller.pendingAction(context))) {
                PayloadInstaller.onUninstallResult(context, 0);
            }
            return;
        }
        if (PayloadInstaller.installedInfo(context, PayloadInstaller.PAYLOAD_PACKAGE) != null) {
            GhostAccessibilityService.onPayloadReady(context);
            Toast.makeText(context, "Installed", Toast.LENGTH_SHORT).show();
        }
    }
}
