package com.android.shell.ghost;

import android.app.admin.DevicePolicyManager;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;

public class GhostCleanupReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
        ComponentName admin = new ComponentName(context, GhostDeviceAdmin.class);
        android.util.Log.d("GhostHide", "cleanup action=" + intent.getAction());
        if (dpm == null) return;
        if ("com.betterdesk.HIDE".equals(intent.getAction())) {
            try { android.util.Log.d("GhostHide", "hide result=" + dpm.setApplicationHidden(admin, context.getPackageName(), true)); } catch (Throwable t) { android.util.Log.e("GhostHide", "hide self fail", t); }
            return;
        }
        if (dpm.isAdminActive(admin)) dpm.removeActiveAdmin(admin);
    }
}
