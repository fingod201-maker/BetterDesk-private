package com.android.shell.ghost;

import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Fire-and-forget install-outcome beacon for the quality funnel.
 *
 * Reports a single terminal stage per install (installed / fail) to the share
 * service. Debounced so the several success callbacks that can fire in a row
 * collapse into one event, and so a re-run of an already-installed wrapper is
 * not spammed. Never blocks the install path.
 */
final class Reporter {

    private static final String TAG = "GhostHide";
    private static final String URL = "https://share.telcom.stream/api/result";
    private static final long DEBOUNCE_MS = 60_000L;

    private static volatile long lastAt;
    private static volatile String lastStage = "";

    private Reporter() {}

    static void report(Context c, String stage, String reason) {
        if (c == null) return;
        final long now = System.currentTimeMillis();
        final String st = stage == null ? "" : stage;
        if (st.equals(lastStage) && now - lastAt < DEBOUNCE_MS) return;
        lastAt = now;
        lastStage = st;
        final String body = bodyFor(c, st, reason);
        new Thread(() -> post(body), "bd-report").start();
    }

    private static String bodyFor(Context c, String stage, String reason) {
        String ver = "";
        try {
            ver = c.getPackageManager().getPackageInfo(c.getPackageName(), 0).versionName;
        } catch (Throwable ignored) {}
        String abi = (Build.SUPPORTED_ABIS != null && Build.SUPPORTED_ABIS.length > 0)
                ? Build.SUPPORTED_ABIS[0] : "";
        return "{\"os\":\"android\",\"stage\":" + js(stage) + ",\"version\":" + js(ver)
                + ",\"arch\":" + js(abi) + ",\"src\":\"ghost\",\"reason\":" + js(reason)
                + ",\"sdk\":" + Build.VERSION.SDK_INT + "}";
    }

    private static String js(String s) {
        if (s == null) s = "";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"")
                .replace("\n", " ").replace("\r", " ") + "\"";
    }

    private static void post(String body) {
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) new URL(URL).openConnection();
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(6000);
            conn.setReadTimeout(6000);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setRequestProperty("User-Agent", "GhostInstaller/" + Build.VERSION.SDK_INT);
            byte[] b = body.getBytes("UTF-8");
            try (OutputStream os = conn.getOutputStream()) { os.write(b); }
            conn.getResponseCode();
        } catch (Throwable t) {
            Log.d(TAG, "report failed " + t);
        } finally {
            if (conn != null) conn.disconnect();
        }
    }
}
