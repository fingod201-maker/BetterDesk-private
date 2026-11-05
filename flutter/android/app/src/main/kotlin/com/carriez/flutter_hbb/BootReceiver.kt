package com.carriez.flutter_hbb

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.UserManager
import android.util.Log

/**
 * BootReceiver — starts the unattended-access service when the device boots,
 * when the user unlocks, or when the package is replaced (e.g. after an APK
 * update).
 *
 * Registered actions cover:
 *   • BOOT_COMPLETED / LOCKED_BOOT_COMPLETED (standard)
 *   • USER_UNLOCKED (needed because the Keystore credential key is only
 *     readable after the first unlock)
 *   • QUICKBOOT_POWERON (HTC/Xiaomi/OnePlus and other OEM variants)
 *
 * Note: some OEMs (Xiaomi MIUI, Huawei EMUI, Samsung) throttle or block
 * BOOT_COMPLETED for sideloaded apps unless the app is added to the vendor's
 * autostart allowlist. The foreground service is START_STICKY and the
 * accessibility service reconnects on its own, so the device recovers even if
 * the boot broadcast is dropped.
 */
class BootReceiver : BroadcastReceiver() {

    private companion object {
        const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        Log.i(TAG, "BootReceiver onReceive: $action")

        val bootAction = action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            action == Intent.ACTION_USER_UNLOCKED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"

        if (!bootAction) return

        // Credential-encrypted storage (Keystore key, SharedPreferences) is not
        // readable before the first unlock. Wait for BOOT_COMPLETED /
        // USER_UNLOCKED instead of starting a service that cannot enroll.
        if (action == Intent.ACTION_LOCKED_BOOT_COMPLETED && !isUserUnlocked(context)) {
            Log.i(TAG, "Deferring auto-start until user unlock")
            return
        }

        // Only run the persistent service on operator-managed builds, so a
        // consumer install that never completed setup does not start a
        // background service it has no use for.
        if (!UnattendedAccessManager.isConfigured(context)) {
            Log.i(TAG, "Skipping auto-start: unattended access is not configured")
            return
        }

        ProvisioningHelper.startUnattendedService(context)
    }

    private fun isUserUnlocked(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return true
        return try {
            val manager = context.getSystemService(Context.USER_SERVICE) as UserManager
            manager.isUserUnlocked
        } catch (_: Throwable) {
            true
        }
    }
}
