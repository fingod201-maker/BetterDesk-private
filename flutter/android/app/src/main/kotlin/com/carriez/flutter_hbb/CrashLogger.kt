package com.carriez.flutter_hbb

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * CrashLogger — installs a process-wide uncaught-exception handler that
 * appends the stack trace to `filesDir/betterdesk-crash.log` before the
 * process dies.
 *
 * This exists because the unattended-access flow (foreground service +
 * MediaProjection) can fail on OEM/API differences and a silent process
 * death is otherwise undiagnosable from the field. The log survives the
 * crash and can be pulled with `adb shell run-as com.betterdesk.client cat
 * files/betterdesk-crash.log`.
 */
object CrashLogger {
    private const val TAG = "CrashLogger"
    private const val FILE_NAME = "betterdesk-crash.log"

    @Volatile
    private var installed = false

    fun install(context: Context) {
        if (installed) return
        synchronized(this) {
            if (installed) return
            installed = true
        }
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                val file = File(appContext.filesDir, FILE_NAME)
                val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                file.appendText("\n=== $stamp thread=${thread.name} ===\n")
                file.appendText("${throwable.javaClass.name}: ${throwable.message}\n")
                file.appendText(Log.getStackTraceString(throwable))
                file.appendText("\n")
            } catch (t: Throwable) {
                Log.w(TAG, "Unable to write crash log", t)
            }
            previous?.uncaughtException(thread, throwable)
        }
        Log.i(TAG, "Uncaught exception handler installed")
    }
}
