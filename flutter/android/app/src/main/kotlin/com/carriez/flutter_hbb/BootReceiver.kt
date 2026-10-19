package com.carriez.flutter_hbb

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * BootReceiver — starts the unattended-access service when the device boots
 * or when the package is replaced (e.g. after an APK update).
 */
class BootReceiver : BroadcastReceiver() {

    private companion object {
        const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        Log.i(TAG, "BootReceiver onReceive: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.MY_PACKAGE_REPLACED") {
            val serviceIntent = Intent(context, UnattendedAccessService::class.java)
                .addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
            // ContextCompat uses startService() below API 26.
            ContextCompat.startForegroundService(context, serviceIntent)
        }
    }
}
