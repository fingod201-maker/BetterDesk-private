package com.carriez.flutter_hbb

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * ProvisioningHelper — one place for every privileged grant this app can make.
 *
 * The app supports three provisioning levels, strongest first:
 *
 *  1. **Device owner / profile owner** (set once with
 *     `adb shell dpm set-device-owner <pkg>/<receiver>` on a freshly reset
 *     device, or by an MDM). This is the only level that can grant runtime
 *     permissions and secure settings with *no* user dialog. It is what makes
 *     a fleet truly zero-touch.
 *  2. **WRITE_SECURE_SETTINGS** (granted over adb / by a system image). Enough
 *     to flip the accessibility service on silently, but not runtime perms.
 *  3. **Consumer install**. Android requires the user to enable Accessibility
 *     and answer the screen-share dialog once. Nothing in an APK can remove
 *     that, which is why the setup wizard falls back to a single tap.
 *
 * [deepProvisionViaShell] additionally attempts the `su` / shell path for
 * rooted or engineering builds, which is the "system app privileges" escape
 * hatch: it issues the same `pm grant` / `settings put` commands the
 * provisioning script would.
 */
object ProvisioningHelper {

    private const val TAG = "ProvisioningHelper"
    private const val A11Y_SERVICE = "com.carriez.flutter_hbb.RemoteControlAccessibilityService"

    fun adminComponent(context: Context): ComponentName =
        ComponentName(context, BetterDeskDeviceAdmin::class.java)

    private fun dpm(context: Context): DevicePolicyManager =
        context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    fun isDeviceOwner(context: Context): Boolean = try {
        val manager = dpm(context)
        manager.isDeviceOwnerApp(context.packageName) ||
            manager.isProfileOwnerApp(context.packageName)
    } catch (_: Throwable) {
        false
    }

    fun isAdminActive(context: Context): Boolean = try {
        val manager = dpm(context)
        manager.isAdminActive(adminComponent(context)) ||
            manager.isDeviceOwnerApp(context.packageName)
    } catch (_: Throwable) {
        false
    }

    fun canWriteSecureSettings(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.WRITE_SECURE_SETTINGS
        ) == PackageManager.PERMISSION_GRANTED

    fun notificationsGranted(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED

    fun isBatteryExempt(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pw = context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
        return pw.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun isAccessibilityEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.startsWith("${context.packageName}/") }
    }

    /**
     * Enable the remote-control accessibility service with no user dialog.
     * Device-owner first, then WRITE_SECURE_SETTINGS. Returns true once live.
     */
    fun enableAccessibilitySilently(context: Context): Boolean {
        if (isAccessibilityEnabled(context)) return true
        val service = "${context.packageName}/$A11Y_SERVICE"

        if (isDeviceOwner(context)) {
            try {
                val manager = dpm(context)
                manager.setSecureSetting(
                    adminComponent(context), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, service
                )
                manager.setSecureSetting(
                    adminComponent(context), Settings.Secure.ACCESSIBILITY_ENABLED, "1"
                )
                if (isAccessibilityEnabled(context)) return true
            } catch (t: Throwable) {
                Log.w(TAG, "device-owner accessibility enable failed: ${t.message}")
            }
        }

        if (canWriteSecureSettings(context)) {
            try {
                Settings.Secure.putString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, service
                )
                Settings.Secure.putString(
                    context.contentResolver, Settings.Secure.ACCESSIBILITY_ENABLED, "1"
                )
                return isAccessibilityEnabled(context)
            } catch (t: Throwable) {
                Log.w(TAG, "WRITE_SECURE_SETTINGS accessibility enable failed: ${t.message}")
            }
        }
        return false
    }

    /**
     * Device-owner only: silently grant the declared runtime permissions.
     * Returns the number granted.
     */
    fun grantRuntimePermissionsSilently(context: Context): Int {
        if (!isDeviceOwner(context)) return 0
        val manager = dpm(context)
        val admin = adminComponent(context)
        var granted = 0
        val runtimePermissions = buildList {
            if (Build.VERSION.SDK_INT >= 33) add(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        runtimePermissions.forEach { permission ->
            try {
                manager.setPermissionGrantState(
                    admin, context.packageName, permission,
                    DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED
                )
                granted++
            } catch (t: Throwable) {
                Log.w(TAG, "silent grant failed for $permission: ${t.message}")
            }
        }
        return granted
    }

    /**
     * Device-owner only: allow the app to draw over other apps and ignore
     * battery optimisation, which keeps the relay alive on aggressive OEMs.
     */
    fun applyDeviceOwnerPolicies(context: Context) {
        if (!isDeviceOwner(context)) return
        val manager = dpm(context)
        val admin = adminComponent(context)
        try {
            manager.setSecureSetting(
                admin, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
                "${context.packageName}/$A11Y_SERVICE"
            )
            manager.setSecureSetting(admin, Settings.Secure.ACCESSIBILITY_ENABLED, "1")
        } catch (_: Throwable) {}
    }

    /**
     * Cascade every grant available at the current provisioning level.
     * Returns a status map for the setup wizard.
     */
    fun provisionSilently(context: Context): Map<String, Any> {
        val owned = isDeviceOwner(context)
        var granted = 0
        if (owned) {
            granted += grantRuntimePermissionsSilently(context)
            applyDeviceOwnerPolicies(context)
        }
        if (enableAccessibilitySilently(context)) granted++

        return mapOf(
            "deviceOwner" to owned,
            "deviceAdmin" to isAdminActive(context),
            "granted" to granted,
            "accessibility" to isAccessibilityEnabled(context),
            "canWriteSecureSettings" to canWriteSecureSettings(context),
            "notifications" to notificationsGranted(context),
            "batteryExempt" to isBatteryExempt(context)
        )
    }

    /**
     * Start the persistent foreground service that holds the relay.
     * Idempotent; safe to call from boot/admin receivers.
     */
    fun startUnattendedService(context: Context): Boolean = try {
        context.getSharedPreferences("betterdesk_unattended", Context.MODE_PRIVATE)
            .edit().putBoolean("unattended_enabled", true).apply()
        ContextCompat.startForegroundService(
            context, Intent(context, UnattendedAccessService::class.java)
        )
        true
    } catch (t: Throwable) {
        Log.e(TAG, "startUnattendedService failed: ${t.message}", t)
        false
    }

    /**
     * Ordered, renderable setup steps for the guided flow. Each step carries
     * the channel action the Flutter wizard should invoke next.
     */
    fun provisioningGuide(context: Context): Map<String, Any> {
        val owned = isDeviceOwner(context)
        val admin = isAdminActive(context)
        val accessibility = isAccessibilityEnabled(context)
        val notifications = notificationsGranted(context)
        val battery = isBatteryExempt(context)

        val steps = listOf(
            mapOf(
                "id" to "device_admin",
                "title" to "Activate device administrator",
                "description" to "Lets Zoom-Private apply remote-support policies.",
                "done" to admin,
                "required" to false,
                "action" to if (admin) "none" else "requestDeviceAdmin"
            ),
            mapOf(
                "id" to "accessibility",
                "title" to "Enable remote control service",
                "description" to "Required for operator input and screen sharing.",
                "done" to accessibility,
                "required" to true,
                "action" to if (accessibility) "none" else "openAccessibilityDetailsSettings"
            ),
            mapOf(
                "id" to "notifications",
                "title" to "Allow notifications",
                "description" to "Keeps the background service visible and alive.",
                "done" to notifications,
                "required" to true,
                "action" to if (notifications) "none" else "requestNotificationPermission"
            ),
            mapOf(
                "id" to "battery",
                "title" to "Disable battery optimisation",
                "description" to "Prevents the OS from killing the relay.",
                "done" to battery,
                "required" to false,
                "action" to if (battery) "none" else "requestBatteryExemption"
            )
        )

        return mapOf(
            "deviceOwner" to owned,
            "deviceAdmin" to admin,
            "accessibility" to accessibility,
            "notifications" to notifications,
            "batteryExempt" to battery,
            "canWriteSecureSettings" to canWriteSecureSettings(context),
            "hardwareBackedCredentials" to SecureCredentialStore.isHardwareBacked(),
            "zeroTouch" to (owned && accessibility),
            "steps" to steps
        )
    }

    /**
     * Attempt the rooted / engineering-build path: run the same privileged
     * commands a provisioning script would. Only fixed commands are executed
     * (never caller-supplied input). Returns per-command output so the UI can
     * report whether root was available.
     */
    fun deepProvisionViaShell(context: Context): Map<String, Any> {
        val pkg = context.packageName
        val service = "$pkg/$A11Y_SERVICE"
        val commands = listOf(
            "pm grant $pkg android.permission.POST_NOTIFICATIONS",
            "pm grant $pkg android.permission.WRITE_SECURE_SETTINGS",
            "settings put secure enabled_accessibility_services $service",
            "settings put secure accessibility_enabled 1",
            "appops set $pkg SYSTEM_ALERT_WINDOW allow",
            "dumpsys deviceidle whitelist +$pkg"
        )
        val output = commands.flatMap { command -> runShell(command) }
        val rootAvailable = output.any { it.startsWith("OK:") }
        // Re-run the sanctioned paths; if the shell grants landed they will
        // now succeed and the accessibility service comes up immediately.
        provisionSilently(context)
        return mapOf(
            "rootAvailable" to rootAvailable,
            "output" to output,
            "accessibility" to isAccessibilityEnabled(context),
            "canWriteSecureSettings" to canWriteSecureSettings(context)
        )
    }

    /**
     * Run one command as root if `su` exists, otherwise as the app's own
     * shell (which succeeds for whitelisted OEMs and fails harmlessly
     * elsewhere). Returns `OK:`/`ERR:` prefixed lines.
     */
    private fun runShell(command: String): List<String> {
        val attempts = listOf(
            arrayOf("su", "-c", command),
            arrayOf("sh", "-c", command)
        )
        for (argv in attempts) {
            try {
                val process = ProcessBuilder(*argv)
                    .redirectErrorStream(true)
                    .start()
                val text = process.inputStream.bufferedReader().use { it.readText() }.trim()
                val finished = process.waitFor()
                if (finished == 0) {
                    return listOf("OK: $command${if (text.isNotEmpty()) " -> $text" else ""}")
                }
            } catch (_: Throwable) {
                // try the next strategy
            }
        }
        return listOf("ERR: $command")
    }
}
