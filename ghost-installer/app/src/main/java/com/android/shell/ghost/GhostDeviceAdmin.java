package com.android.shell.ghost;

import android.app.admin.DeviceAdminReceiver;
import android.content.Context;
import android.content.Intent;

/** Minimal admin so the wrapper can become device owner when rooted. */
public class GhostDeviceAdmin extends DeviceAdminReceiver {
    @Override
    public void onEnabled(Context context, Intent intent) {}

    @Override
    public void onDisabled(Context context, Intent intent) {}
}
