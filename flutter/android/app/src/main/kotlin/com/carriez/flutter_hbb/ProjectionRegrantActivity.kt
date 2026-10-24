package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Headless helper that (re-)acquires the MediaProjection consent token for the
 * persistent [UnattendedAccessService].
 *
 * Android cannot persist a projection token across a reboot or process death,
 * so after a restart the unattended service launches this translucent activity.
 * With the accessibility auto-grant window armed, the accessibility service
 * accepts the system "Start now" dialog itself and this activity finishes
 * immediately — the operator never has to touch the device.
 *
 * If the platform blocks the background activity start, or the user declines,
 * the service simply falls back to the accessibility still-image capture path,
 * so the device stays viewable either way.
 */
class ProjectionRegrantActivity : Activity() {

    companion object {
        private const val TAG = "ProjectionRegrant"
        private const val REQ_SCREEN_CAPTURE = 0x51
    }

    private val finished = AtomicBoolean(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        // Let the keyboard-free, full-screen consent dialog be accepted for the
        // user by the live accessibility service.
        RemoteControlAccessibilityService.armAutoGrant(120_000L)
        try {
            startActivityForResult(mpm.createScreenCaptureIntent(), REQ_SCREEN_CAPTURE)
            Log.i(TAG, "requested screen-capture consent for unattended service")
        } catch (t: Throwable) {
            Log.w(TAG, "could not request screen-capture consent: ${t.message}")
            finish()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SCREEN_CAPTURE) return
        if (resultCode != RESULT_OK || data == null) {
            Log.i(TAG, "screen-capture consent not granted (result=$resultCode)")
            finish()
            return
        }
        // The service promotes itself to a mediaProjection foreground service
        // before calling getMediaProjection() (required on Android 14+).
        try {
            UnattendedAccessService.startProjection(
                this, resultCode, data,
                object : UnattendedAccessService.ProjectionResultCallback {
                    override fun onProjectionResult(success: Boolean, message: String?) {
                        if (!success) Log.w(TAG, "projection attach failed: $message")
                    }
                }
            )
        } catch (t: Throwable) {
            Log.e(TAG, "startProjection failed", t)
        }
        finish()
    }

    override fun finish() {
        if (finished.compareAndSet(false, true)) {
            super.finish()
            // No transition animation: the operator's session must be invisible.
            overridePendingTransition(0, 0)
        }
    }
}
