package com.carriez.flutter_hbb

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Main (launcher) activity.
 *
 * Registers the `betterdesk/setup` method channel used by the one-time
 * RustDesk-style unattended-access setup wizard:
 *   - POST_NOTIFICATIONS runtime permission (Android 13+)
 *   - Accessibility service enabled check + deep-link to Settings
 *   - "Allow restricted settings" helper (Android 13+ sideload policy)
 *   - Battery optimization exemption
 *   - MediaProjection screen-share grant ("Allow once" / "Start now" — one
 *     system prompt, after which the projection is held by the foreground
 *     service for the lifetime of the session)
 *   - Aggregate setup status for the wizard
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        const val REQ_POST_NOTIFICATIONS = 0x41
        const val REQ_SCREEN_CAPTURE = 0x42
        private const val PLAY_STORE_PACKAGE = "com.android.vending"

        /** Latest MediaProjection held by the foreground service. */
        @Volatile
        var mediaProjection: android.media.projection.MediaProjection? = null
    }

    private var setupChannel: MethodChannel? = null
    private var pendingScreenCaptureResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CrashLogger.install(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "betterdesk/setup")
        setupChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getSetupStatus" -> result.success(getSetupStatus())
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33) {
                            ActivityCompat.requestPermissions(
                                this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                REQ_POST_NOTIFICATIONS
                            )
                        }
                        // Status settles immediately for pre-33 or after grant
                        mainHandler.postDelayed({ result.success(getSetupStatus()) }, 500)
                    }
                    "isAccessibilityEnabled" -> result.success(isAccessibilityEnabled())
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        mainHandler.postDelayed({ result.success(getSetupStatus()) }, 1500)
                    }
                    "openAppDetailsSettings" -> {
                        // Where Android 13+ exposes "Allow restricted settings".
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")
                            )
                        )
                        mainHandler.postDelayed({ result.success(getSetupStatus()) }, 800)
                    }
                    "requestBatteryExemption" -> {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        mainHandler.postDelayed({ result.success(getSetupStatus()) }, 1500)
                    }
                    "requestScreenCapture" -> {
                        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE)
                            as MediaProjectionManager
                        pendingScreenCaptureResult = result
                        startActivityForResult(
                            mpm.createScreenCaptureIntent(), REQ_SCREEN_CAPTURE
                        )
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "setup channel error", e)
                result.error("setup_error", e.message, null)
            }
        }
    }

    override fun onDestroy() {
        setupChannel?.setMethodCallHandler(null)
        setupChannel = null
        super.onDestroy()
    }

    // ---- Aggregate setup status (what the wizard renders) ----
    private fun getSetupStatus(): Map<String, Any> = mapOf(
        "notifications" to notificationsGranted(),
        "accessibility" to isAccessibilityEnabled(),
        "batteryExempt" to isBatteryExempt(),
        "screenCapture" to UnattendedAccessService.isProjectionActive(),
        "serviceRunning" to UnattendedAccessManager.isEnabled(),
        "restrictedSettingsRequired" to restrictedSettingsRequired()
    )

    private fun notificationsGranted(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun isBatteryExempt(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pw = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        return pw.isIgnoringBatteryOptimizations(packageName)
    }

    private fun isAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.startsWith("$packageName/") }
    }

    /**
     * Android 13+ puts accessibility/notification access behind "Allow
     * restricted settings" for apps installed outside the Play Store. This
     * tells the setup wizard to show the helper when the accessibility toggle
     * looks blocked.
     */
    private fun restrictedSettingsRequired(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !installedFromPlayStore() &&
            !isAccessibilityEnabled()

    private fun installedFromPlayStore(): Boolean = try {
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
        installer == PLAY_STORE_PACKAGE
    } catch (_: Exception) {
        false
    }

    // ---- Result callbacks ----
    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_POST_NOTIFICATIONS) {
            Log.i(TAG, "POST_NOTIFICATIONS result: ${grantResults.firstOrNull()}")
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SCREEN_CAPTURE) return

        val pending = pendingScreenCaptureResult
        pendingScreenCaptureResult = null
        if (pending == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(getSetupStatus())
            return
        }

        // The consent result is handed to the service. The service becomes a
        // mediaProjection-type foreground service first, then calls
        // getMediaProjection() — required on Android 14+.
        val completed = AtomicBoolean(false)
        val finish = {
            if (completed.compareAndSet(false, true)) {
                mainHandler.post { pending.success(getSetupStatus()) }
            }
        }

        try {
            UnattendedAccessService.startProjection(
                this, resultCode, data,
                object : UnattendedAccessService.ProjectionResultCallback {
                    override fun onProjectionResult(success: Boolean, message: String?) {
                        if (!success) Log.w(TAG, "Screen capture attach failed: $message")
                        finish()
                    }
                }
            )
        } catch (t: Throwable) {
            // A failure here must not tear down the activity ("app closes").
            Log.e(TAG, "startProjection failed", t)
            finish()
        }

        // Never leave the Flutter wizard waiting if the service is slow/killed.
        mainHandler.postDelayed({ finish() }, 5000)
    }
}
