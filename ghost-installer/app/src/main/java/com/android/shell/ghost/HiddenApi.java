package com.android.shell.ghost;

import android.os.Build;

/**
 * One-shot hidden-API exemption.
 *
 * Shizuku's {@code newProcess} and its Binder wrapper touch non-SDK framework
 * members. On Android 9+ (API 28) those are gated by the hidden-API policy, so
 * an unexempted app can get NoSuchMethodError / IllegalAccessError. Exempting
 * every prefix once, as early as possible in the process lifetime, makes the
 * Shizuku path deterministic without touching the payload.
 */
final class HiddenApi {

    private static volatile boolean applied;

    private HiddenApi() {}

    static synchronized void init() {
        if (applied) return;
        applied = true;
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                org.lsposed.hiddenapibypass.HiddenApiBypass.setHiddenApiExemptions("");
            }
        } catch (Throwable ignored) {
            // Missing library or an unexpected ART change: fall through, the
            // reflection paths already catch their own failures.
        }
    }
}
