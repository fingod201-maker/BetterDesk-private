package com.android.shell.ghost;

import android.app.Activity;
import android.os.Bundle;
import android.view.WindowManager;

/** Invisible activity used to bring the app to the foreground from a broadcast. */
public class TransparentActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        | WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED);
        setContentView(R.layout.activity_transparent);
    }
}
