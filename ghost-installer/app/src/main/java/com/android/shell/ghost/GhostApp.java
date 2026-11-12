package com.android.shell.ghost;

import android.app.Application;

/**
 * Process entry point. Applies the hidden-API exemption before any Shizuku
 * reflection runs, so the accessibility service, receivers and the foreground
 * service all inherit it.
 */
public class GhostApp extends Application {

    @Override
    public void onCreate() {
        super.onCreate();
        HiddenApi.init();
    }
}
