package com.carriez.flutter_hbb

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
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
import android.view.WindowManager
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
        const val REQ_DEVICE_ADMIN = 0x43
        private const val PLAY_STORE_PACKAGE = "com.android.vending"

        /** Latest MediaProjection held by the foreground service. */
        @Volatile
        var mediaProjection: android.media.projection.MediaProjection? = null
    }

    private var setupChannel: MethodChannel? = null
    private var pendingScreenCaptureResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingDeviceAdminResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CrashLogger.install(this)
        // Let the auto-grant window be persisted even before the accessibility
        // service binds (survives a process restart mid-setup).
        RemoteControlAccessibilityService.attachContext(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "betterdesk/setup")
        setupChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getSetupStatus" -> result.success(getSetupStatus())
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 && !notificationsGranted()) {
                            pendingNotificationResult = result
                            ActivityCompat.requestPermissions(
                                this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                                REQ_POST_NOTIFICATIONS
                            )
                            mainHandler.postDelayed({
                                completeNotificationRequest()
                            }, 8000)
                        } else {
                            result.success(getSetupStatus())
                        }
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
                        // If the accessibility service is live it will accept the
                        // "Start now" dialog for the user (one-tap flow).
                        RemoteControlAccessibilityService.armAutoGrant()
                        pendingScreenCaptureResult = result
                        startActivityForResult(
                            mpm.createScreenCaptureIntent(), REQ_SCREEN_CAPTURE
                        )
                    }
                    "getBakedServerConfig" -> result.success(bakedServerConfig())
                    "getRelayStatus" -> result.success(
                        mapOf(
                            "state" to AgentRelayBridge.state(),
                            "deviceId" to AgentRelayBridge.currentDeviceId(this)
                        )
                    )
                    "startUnattendedAccess" -> {
                        result.success(startUnattendedAccess())
                    }
                    "grantAllSilently" -> result.success(grantAllSilently())
                    "enableAccessibilitySilently" -> result.success(enableAccessibilitySilently())
                    "isDeviceAdmin" -> result.success(isDeviceAdmin())
                    "requestDeviceAdmin" -> requestDeviceAdmin(result)
                    "armAutoGrant" -> {
                        RemoteControlAccessibilityService.armAutoGrant()
                        result.success(true)
                    }
                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "autoProvision" -> {
                        try {
                            RemoteControlAccessibilityService.armAutoGrant()
                            grantAllSilently()
                            enableAccessibilitySilently()
                            result.success(mapOf("ok" to true))
                        } catch (t: Throwable) {
                            result.error("auto_provision", t.message, null)
                        }
                    }
                    "setInvisible" -> {
                        goInvisible()
                        result.success(true)
                    }
                    "disarmAutoGrant" -> {
                        RemoteControlAccessibilityService.disarmAutoGrant()
                        result.success(true)
                    }
                    "openAccessibilityDetailsSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val details = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                startActivity(details)
                            } else {
                                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            }
                        } catch (_: Throwable) {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        }
                        mainHandler.postDelayed({ result.success(getSetupStatus()) }, 800)
                    }
                    "requestSystemAlertWindow" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                            startActivity(intent)
                            mainHandler.postDelayed({ result.success(Settings.canDrawOverlays(this)) }, 1500)
                        } else {
                            result.success(true)
                        }
                    }
                    "getProvisioningGuide" -> result.success(
                        ProvisioningHelper.provisioningGuide(this)
                    )
                    "isDeviceOwner" -> result.success(
                        ProvisioningHelper.isDeviceOwner(this)
                    )
                    "secureStorageStatus" -> result.success(
                        mapOf("hardwareBacked" to SecureCredentialStore.isHardwareBacked())
                    )
                    "requestDeviceOwner" -> result.success(deviceOwnerGuide())
                    "deepProvision" -> {
                        try {
                            result.success(ProvisioningHelper.deepProvisionViaShell(this))
                        } catch (t: Throwable) {
                            result.error("deep_provision", t.message, null)
                        }
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

    // ---- Auto-connect bridge -------------------------------------------

    /** Operator endpoint baked into Android resources by CI. */
    private fun bakedServerConfig(): Map<String, Any> {
        val res = resources
        fun baked(name: String): String? {
            val id = res.getIdentifier(name, "string", packageName)
            return if (id != 0) res.getString(id) else null
        }
        val host = baked("betterdesk_server_host")?.trim().orEmpty()
        val https = (baked("betterdesk_use_https") ?: "true")
            .let { !(it.equals("false", true) || it == "0" || it.equals("n", true)) }
        val port = (baked("betterdesk_server_port")
            ?: baked("betterdesk_operator_port"))?.trim()?.toIntOrNull() ?: 0
        return mapOf(
            "host" to host,
            "useHttps" to https,
            "port" to port,
            "apiHost" to (baked("betterdesk_api_host")?.trim().orEmpty())
        )
    }

    /**
     * Device-owner provisioning cannot be triggered by an APK: Android requires
     * a freshly reset device and a privileged (adb/MDM) caller. Return the
     * exact one-time command so the guided flow can display it.
     */
    private fun deviceOwnerGuide(): Map<String, Any> {
        val component = "$packageName/${BetterDeskDeviceAdmin::class.java.name}"
        return mapOf(
            "alreadyOwner" to ProvisioningHelper.isDeviceOwner(this),
            "canSetProgrammatically" to false,
            "adbCommand" to "adb shell dpm set-device-owner $component",
            "notes" to "Run once on a freshly reset device, before adding any accounts."
        )
    }

    /** Starts the persistent unattended-access service (real relay dialer). */
    private fun startUnattendedAccess(): Boolean =
        ProvisioningHelper.startUnattendedService(this)

    /** True when the app was granted WRITE_SECURE_SETTINGS at provisioning time. */
    private fun canWriteSecureSettings(): Boolean =
        ProvisioningHelper.canWriteSecureSettings(this)

    /**
     * Enable the remote-control accessibility service with no user dialog.
     *
     * Two sanctioned paths, checked in order:
     *   1. Device owner / profile owner → DevicePolicyManager.setSecureSetting.
     *   2. Provisioned WRITE_SECURE_SETTINGS (granted by the fleet provisioning
     *      script over adb) → write Settings.Secure directly.
     *
     * On an ordinary consumer install neither is available, so this returns
     * false and the wizard shows the single Accessibility toggle. Android does
     * not permit an app to enable its own accessibility service otherwise.
     */
    private fun enableAccessibilitySilently(): Boolean =
        ProvisioningHelper.enableAccessibilitySilently(this)

    /**
     * Cascade every grant the app can apply without a dialog:
     *   - device owner: notifications + all declared runtime permissions + a11y;
     *   - provisioned WRITE_SECURE_SETTINGS: accessibility;
     *   - otherwise: reporting only (the wizard completes the single toggle).
     * Returns a status map so the Dart wizard can decide whether another step
     * is genuinely required (it should not be on a provisioned device).
     */
    private fun grantAllSilently(): Map<String, Any> =
        ProvisioningHelper.provisionSilently(this)

    private fun deviceAdminComponent(): ComponentName =
        ProvisioningHelper.adminComponent(this)

    private fun isDeviceAdmin(): Boolean =
        ProvisioningHelper.isAdminActive(this)

    /**
     * Single privileged permission for the one-tap flow. Activates the device
     * admin (one system dialog on consumer devices, already active on
     * device-owner fleets). Once active the app can cascade the remaining
     * grants: device-owner installs apply them silently, and the accessibility
     * service auto-accepts the residual system dialogs.
     */
    private fun requestDeviceAdmin(result: MethodChannel.Result) {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = deviceAdminComponent()
        if (dpm.isAdminActive(admin) || dpm.isDeviceOwnerApp(packageName)) {
            RemoteControlAccessibilityService.armAutoGrant()
            result.success(true)
            return
        }
        pendingDeviceAdminResult = result
        RemoteControlAccessibilityService.armAutoGrant()
        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "Required to enable hands-free remote support for this device."
            )
        }
        try {
            startActivityForResult(intent, REQ_DEVICE_ADMIN)
        } catch (t: Throwable) {
            Log.w(TAG, "device admin intent failed: ${t.message}")
            pendingDeviceAdminResult = null
            result.success(false)
        }
        // Never leave Flutter waiting if the system dialog is dismissed oddly.
        mainHandler.postDelayed({ completeDeviceAdminRequest() }, 60000)
    }

    private fun completeDeviceAdminRequest() {
        val pending = pendingDeviceAdminResult ?: return
        pendingDeviceAdminResult = null
        pending.success(isDeviceAdmin())
    }

    /**
     * Post-connection stealth mode: make the window invisible and
     * non-interactive, then send the task to the background so the operator
     * service keeps running without blocking the end user's own activity.
     */
    private fun goInvisible() {
        mainHandler.post {
            try {
                val attrs = window.attributes
                attrs.alpha = 0f
                window.attributes = attrs
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                )
            } catch (t: Throwable) {
                Log.w(TAG, "goInvisible failed: ${t.message}")
            }
            moveTaskToBack(true)
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            val attrs = window.attributes
            attrs.alpha = 1f
            window.attributes = attrs
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            )
        } catch (_: Throwable) {}
    }

    private fun completeNotificationRequest() {
        val pending = pendingNotificationResult ?: return
        pendingNotificationResult = null
        pending.success(getSetupStatus())
    }

    // ---- Aggregate setup status (what the wizard renders) ----
    private fun getSetupStatus(): Map<String, Any> = mapOf(
        "notifications" to notificationsGranted(),
        "accessibility" to isAccessibilityEnabled(),
        "batteryExempt" to isBatteryExempt(),
        "screenCapture" to UnattendedAccessService.isProjectionActive(),
        "accessibilityScreenshot" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && isAccessibilityEnabled()),
        "serviceRunning" to (try { 
            val svc = UnattendedAccessService.isRunning() 
            if (svc) svc else UnattendedAccessManager.isEnabled()
        } catch (_: Throwable) { UnattendedAccessManager.isEnabled() }),
        "restrictedSettingsRequired" to restrictedSettingsRequired(),
        "deviceOwner" to ProvisioningHelper.isDeviceOwner(this),
        "deviceAdmin" to ProvisioningHelper.isAdminActive(this),
        "canWriteSecureSettings" to canWriteSecureSettings(),
        "hardwareBackedCredentials" to SecureCredentialStore.isHardwareBacked()
    )

    private fun notificationsGranted(): Boolean =
        ProvisioningHelper.notificationsGranted(this)

    private fun isBatteryExempt(): Boolean =
        ProvisioningHelper.isBatteryExempt(this)

    private fun isAccessibilityEnabled(): Boolean =
        ProvisioningHelper.isAccessibilityEnabled(this)

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
            completeNotificationRequest()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_DEVICE_ADMIN) {
            completeDeviceAdminRequest()
            return
        }
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
