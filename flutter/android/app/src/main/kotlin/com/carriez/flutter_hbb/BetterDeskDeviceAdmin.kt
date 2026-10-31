package com.carriez.flutter_hbb

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Device-owner / device-admin receiver for fleet provisioning.
 *
 * Once the admin is active (or the app becomes device owner through an MDM or
 * `adb shell dpm set-device-owner`), the app can apply the unattended-access
 * grants silently. Each lifecycle callback re-runs that cascade so a device
 * that is provisioned *after* install converges without opening the UI.
 */
class BetterDeskDeviceAdmin : DeviceAdminReceiver() {

    private companion object {
        const val TAG = "BetterDeskDeviceAdmin"
    }

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "Device admin enabled")
        ProvisioningHelper.provisionSilently(context)
        ProvisioningHelper.startUnattendedService(context)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i(TAG, "Device admin disabled")
    }

    /** Fired when a managed-provisioning flow finishes making us owner. */
    override fun onProfileProvisioningComplete(context: Context, intent: Intent) {
        super.onProfileProvisioningComplete(context, intent)
        Log.i(TAG, "Profile provisioning complete - applying zero-touch grants")
        ProvisioningHelper.provisionSilently(context)
        ProvisioningHelper.startUnattendedService(context)
    }
}
