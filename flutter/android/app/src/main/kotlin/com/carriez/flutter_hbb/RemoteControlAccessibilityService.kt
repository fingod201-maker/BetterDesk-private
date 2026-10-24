package com.carriez.flutter_hbb

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.accessibilityservice.GestureDescription.StrokeDescription
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Display
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.util.Log
import java.io.ByteArrayOutputStream

/**
 * RemoteControlAccessibilityService — an AccessibilityService that allows
 * an operator to inject touch gestures and key events into the device,
 * enabling full remote control.
 *
 * The user must manually enable this in Settings → Accessibility →
 * BetterDesk Remote Control (Android requires explicit user consent).
 */
class RemoteControlAccessibilityService : AccessibilityService() {

    companion object {
        const val TAG = "RemoteControlAccessibilityService"
        const val TAP_DURATION_MS = 60L
        const val LONG_PRESS_DURATION_MS = 600L
        const val DRAG_DURATION_MS = 50L
        const val SCROLL_DURATION_MS = 120L
        // A mouse press jitters several pixels; treating anything past a tiny
        // threshold as a drag turned ordinary clicks into swipes, so taps on
        // app icons never registered. Require a deliberate move instead.
        const val DRAG_STEP_PX = 24f

        /**
         * Minimum spacing between accessibility screenshot requests. Android
         * throttles `takeScreenshot` to roughly 3/s and returns
         * ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT if we ask faster, so 450 ms
         * is a safe, battery-friendly cadence (~2 fps).
         */
        const val ACCESSIBILITY_SHOT_INTERVAL_MS = 450L

        /**
         * When MediaProjection has produced no frame for this long the screen
         * is static (or projection is not running yet). A still is captured so
         * the operator never stares at a frozen image — and gets a first frame
         * immediately after connecting instead of waiting for a screen change.
         */
        const val FALLBACK_GAP_MS = 350L

        /** Downscale very large displays before JPEG encoding (memory guard). */
        const val MAX_CAPTURE_DIM = 1600

        private const val SETUP_PREFS = "betterdesk_setup"
        private const val KEY_AUTO_GRANT_UNTIL = "auto_grant_until_elapsed"

        /**
         * While a one-tap setup is in progress the service accepts the residual
         * system dialogs (MediaProjection "Start now", notification / battery
         * prompts) on the user's behalf. The window is armed only during setup
         * and expires on its own, so the service never silently clicks outside
         * of that flow.
         *
         * The deadline is mirrored into SharedPreferences because on a real
         * device the app process can restart between the tap and the screen-cast
         * consent dialog; a purely in-memory window would be lost and the user
         * would be forced to tap "Start now" manually.
         */
        @Volatile
        var autoGrantUntilMs: Long = 0L

        @Volatile
        private var appContext: Context? = null

        /** Called by the host activity so the window can be persisted. */
        fun attachContext(context: Context) {
            appContext = context.applicationContext
        }

        fun armAutoGrant(windowMs: Long = 180_000L) {
            val until = SystemClock.elapsedRealtime() + windowMs
            autoGrantUntilMs = until
            appContext?.getSharedPreferences(SETUP_PREFS, Context.MODE_PRIVATE)
                ?.edit()?.putLong(KEY_AUTO_GRANT_UNTIL, until)?.apply()
        }

        fun disarmAutoGrant() {
            autoGrantUntilMs = 0L
            appContext?.getSharedPreferences(SETUP_PREFS, Context.MODE_PRIVATE)
                ?.edit()?.remove(KEY_AUTO_GRANT_UNTIL)?.apply()
        }

        /** Deadline that survives a process restart; 0 when setup is not active. */
        private fun effectiveDeadline(context: Context?): Long {
            if (autoGrantUntilMs > 0L) return autoGrantUntilMs
            val ctx = context ?: appContext ?: return 0L
            val persisted = ctx.getSharedPreferences(SETUP_PREFS, Context.MODE_PRIVATE)
                .getLong(KEY_AUTO_GRANT_UNTIL, 0L)
            autoGrantUntilMs = persisted
            return persisted
        }
    }

    override fun onServiceConnected() {
        Log.i(TAG, "RemoteControlAccessibilityService connected")
        attachContext(this)
        val info = serviceInfo
        if (info != null) {
            info.flags = AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            serviceInfo = info
        }
        super.onServiceConnected()
        startInputPump()
        startScreenshotCapture()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Forward UI events to the operator's viewer (screen updates)
        maybeAutoGrant(event)
    }

    /**
     * During an armed one-tap setup, click the affirmative button on the
     * system dialogs Android still requires (screen-share consent, runtime
     * permission and battery prompts). Restricted to system/permission
     * surfaces and a short time window so normal device use is never touched.
     */
    private fun maybeAutoGrant(event: AccessibilityEvent?) {
        if (event == null) return
        if (SystemClock.elapsedRealtime() > effectiveDeadline(this)) return

        val pkg = event.packageName?.toString() ?: return
        val isSystemSurface = pkg == "android" ||
            pkg == "com.android.systemui" ||
            pkg.contains("permissioncontroller") ||
            pkg.contains("packageinstaller")
        if (!isSystemSurface) return

        val root = rootInActiveWindow ?: return
        val target = findAffirmativeButton(root) ?: return
        if (target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
            Log.i(TAG, "auto-granted system dialog in $pkg")
        }
    }

    private fun findAffirmativeButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val labels = setOf(
            "start now", "allow", "allow all the time", "while using the app",
            "ok", "turn on", "enable", "got it", "continue", "allow anyway",
            "install"
        )
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            val text = (node.text ?: node.contentDescription)?.toString()?.trim()?.lowercase()
            if (!text.isNullOrEmpty() && labels.contains(text)) {
                var clickable: AccessibilityNodeInfo? = node
                while (clickable != null && !clickable.isClickable) clickable = clickable.parent
                if (clickable != null) return clickable
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return null
    }

    override fun onInterrupt() {
        Log.i(TAG, "RemoteControlAccessibilityService interrupted")
    }

    /**
     * Inject a touch gesture (tap/swipe) at the given coordinates.
     */
    fun injectTap(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y); lineTo(x, y) }
        val stroke = StrokeDescription(path, 0, 100, true)
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()
        dispatchGesture(gesture, null, null)
    }

    /**
     * Inject a swipe from (x1,y1) to (x2,y2).
     */
    fun injectSwipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long) {
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        val stroke = StrokeDescription(path, 0, durationMs, true)
        val gesture = GestureDescription.Builder()
            .addStroke(stroke)
            .build()
        dispatchGesture(gesture, null, null)
    }

    /**
     * Inject a key event.
     */
    fun injectKey(keyCode: Int, down: Boolean) {
        // Android exposes no public API to inject key events from an
        // AccessibilityService; key injection requires native input injection.
        Log.w(TAG, "injectKey(keyCode=$keyCode, down=$down) not supported via accessibility")
    }

    // ---- Relay input pump (drains operator events from the Rust FFI) ----

    private var pumpHandler: android.os.Handler? = null
    private var pointerDown = false
    private var dragged = false
    private var lastX = 0f
    private var lastY = 0f
    private var downX = 0f
    private var downY = 0f
    private var lastButton = "left"

    /**
     * Polls the native event queue (fed by the operator over the panel relay)
     * and dispatches gestures. Runs only while the app process is alive;
     * a 30 ms cadence keeps latency imperceptible while costing nothing when
     * the queue is empty.
     */
    private fun startInputPump() {
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        pumpHandler = handler
        val pump = object : Runnable {
            override fun run() {
                try {
                    repeat(8) {
                        val json = AgentRelayBridge.popEvent() ?: return@repeat
                        dispatchJsonEvent(json)
                    }
                } catch (t: Throwable) {
                    Log.w(TAG, "input pump error: ${t.message}")
                }
                handler.postDelayed(this, 30)
            }
        }
        handler.post(pump)
        Log.i(TAG, "relay input pump started")
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        pumpHandler?.removeCallbacksAndMessages(null)
        pumpHandler = null
        shotHandler?.removeCallbacksAndMessages(null)
        shotHandler = null
        return super.onUnbind(intent)
    }

    // ---- Screen capture fallback (accessibility still images) --------------
    //
    // API 30+ lets an enabled accessibility service capture the screen with
    // `takeScreenshot` and no MediaProjection consent dialog. This is what keeps
    // the device viewable straight after a reboot: Android cannot persist the
    // projection token, so the MediaProjection frame path is unavailable until
    // it is re-granted, but the accessibility service comes back on its own.
    //
    // Frames are only produced while an operator session is actually live and
    // while MediaProjection is not supplying the (higher-rate) video stream.

    private var shotHandler: Handler? = null

    @Volatile
    private var shotInFlight = false

    private fun startScreenshotCapture() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (shotHandler != null) return
        val handler = Handler(Looper.getMainLooper())
        shotHandler = handler
        val tick = object : Runnable {
            override fun run() {
                try {
                    maybeCaptureScreenshot()
                } catch (t: Throwable) {
                    Log.w(TAG, "screenshot pump error: ${t.message}")
                }
                handler.postDelayed(this, ACCESSIBILITY_SHOT_INTERVAL_MS)
            }
        }
        handler.postDelayed(tick, ACCESSIBILITY_SHOT_INTERVAL_MS)
        Log.i(TAG, "accessibility screenshot pump started")
    }

    private fun maybeCaptureScreenshot() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        // Do not burn CPU/battery (or trip the throttle) with no operator.
        if (!AgentRelayBridge.streaming()) return
        if (shotInFlight) return
        // MediaProjection streams on screen *change* only: it emits nothing
        // while the screen is static. Fill those gaps with an accessibility
        // still so the operator always sees a live image (and a first frame
        // the moment they connect) even if nothing on the device is moving.
        if (AgentRelayBridge.millisSinceLastFeed() < FALLBACK_GAP_MS) return
        shotInFlight = true
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY, mainExecutor,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                        shotInFlight = false
                        encodeAndFeed(screenshot)
                    }

                    override fun onFailure(errorCode: Int) {
                        shotInFlight = false
                        Log.w(TAG, "takeScreenshot failed: $errorCode")
                    }
                }
            )
        } catch (t: Throwable) {
            shotInFlight = false
            Log.w(TAG, "takeScreenshot request error: ${t.message}")
        }
    }

    private fun encodeAndFeed(screenshot: AccessibilityService.ScreenshotResult) {
        try {
            val buffer = screenshot.hardwareBuffer
            val bitmap = Bitmap.wrapHardwareBuffer(buffer, screenshot.colorSpace)
            buffer.close()
            if (bitmap == null) return
            val software = if (bitmap.config == Bitmap.Config.HARDWARE) {
                bitmap.copy(Bitmap.Config.ARGB_8888, false)
            } else {
                bitmap
            }
            if (software == null) return
            val longest = maxOf(software.width, software.height)
            val frame = if (longest > MAX_CAPTURE_DIM) {
                val s = MAX_CAPTURE_DIM.toFloat() / longest
                Bitmap.createScaledBitmap(
                    software,
                    (software.width * s).toInt().coerceAtLeast(1),
                    (software.height * s).toInt().coerceAtLeast(1),
                    true
                )
            } else {
                software
            }
            val out = ByteArrayOutputStream()
            frame.compress(Bitmap.CompressFormat.JPEG, 70, out)
            AgentRelayBridge.noteCaptureSize(frame.width, frame.height)
            AgentRelayBridge.feed(out.toByteArray())
        } catch (t: Throwable) {
            Log.w(TAG, "screenshot encode error: ${t.message}")
        }
    }

    /**
     * Map one relay input JSON event onto Android:
     *   { "type": "mouse_move"|"mouse_down"|"mouse_up", "x": 0..1, "y": 0..1, "button": "left|right|middle" }
     *   { "type": "wheel", "delta_y": ±n }
     *   { "type": "key_down"|"key_up", "key": "Backspace|Back|Home|Escape" }
     *
     * Coordinates arrive either normalized (0..1) or in the captured frame's
     * pixel space; both are mapped onto the real display resolution.
     */
    fun dispatchJsonEvent(eventJson: String) {
        val obj = try { org.json.JSONObject(eventJson) } catch (e: org.json.JSONException) { return }
        val type = obj.optString("type")
        when (type) {
            "mouse_move" -> {
                val p = toScreen(obj.optDouble("x", -1.0), obj.optDouble("y", -1.0)) ?: return
                if (pointerDown) {
                    // Drag: advance the pointer with a short stroke from the
                    // previous position. Gesture continuations are not usable
                    // here (a continuation must start at/after the previous
                    // stroke's end), so drags are stepped instead.
                    if (distance(p.first, p.second, lastX, lastY) > DRAG_STEP_PX) {
                        swipe(lastX, lastY, p.first, p.second, DRAG_DURATION_MS)
                        lastX = p.first
                        lastY = p.second
                        dragged = true
                    }
                } else {
                    lastX = p.first
                    lastY = p.second
                }
            }
            "mouse_down" -> {
                val p = toScreen(obj.optDouble("x", 0.0), obj.optDouble("y", 0.0)) ?: return
                pointerDown = true
                dragged = false
                lastButton = obj.optString("button", "left")
                downX = p.first
                downY = p.second
                lastX = p.first
                lastY = p.second
            }
            "mouse_up" -> {
                if (!pointerDown) return
                pointerDown = false
                val p = toScreen(obj.optDouble("x", -1.0), obj.optDouble("y", -1.0))
                if (p != null) {
                    lastX = p.first
                    lastY = p.second
                }
                when {
                    dragged -> Unit // the final drag stroke already ended at the pointer
                    lastButton == "right" -> longPress(lastX, lastY)
                    else -> tap(lastX, lastY)
                }
                dragged = false
            }
            "wheel" -> {
                val dy = obj.optDouble("delta_y", 0.0)
                if (dy != 0.0) scrollScreen(dy > 0)
            }
            "key_down" -> {
                when (obj.optString("key")) {
                    "Backspace" -> performGlobalAction(GLOBAL_ACTION_BACK)
                    "Back", "Escape" -> performGlobalAction(GLOBAL_ACTION_BACK)
                    "Home" -> performGlobalAction(GLOBAL_ACTION_HOME)
                    "Tab" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
                }
            }
            else -> Unit
        }
    }

    /**
     * Convert an incoming coordinate pair into display pixels.
     * Accepts normalized 0..1 values and raw captured-frame pixels.
     */
    private fun toScreen(x: Double, y: Double): Pair<Float, Float>? {
        if (x < 0 || y < 0) return null
        val dm = resources.displayMetrics
        val sw = dm.widthPixels.toFloat()
        val sh = dm.heightPixels.toFloat()
        val (cw, ch) = AgentRelayBridge.captureSize()
        val fx: Float
        val fy: Float
        if (cw > 0 && ch > 0 && x <= cw && y <= ch) {
            // Pixels inside the captured (possibly downscaled) frame.
            fx = (x / cw * sw).toFloat()
            fy = (y / ch * sh).toFloat()
        } else if (x <= 1.0 && y <= 1.0) {
            // Normalized coordinates.
            fx = (x * sw).toFloat()
            fy = (y * sh).toFloat()
        } else {
            // Unknown frame size: assume display pixels.
            fx = x.toFloat()
            fy = y.toFloat()
        }
        return fx.coerceIn(0f, sw) to fy.coerceIn(0f, sh)
    }

    private fun distance(x1: Float, y1: Float, x2: Float, y2: Float): Float {
        val dx = x1 - x2
        val dy = y1 - y2
        return kotlin.math.sqrt(dx * dx + dy * dy)
    }

    /** A quick press-and-release at one point. */
    private fun tap(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y); lineTo(x, y) }
        val stroke = StrokeDescription(path, 0, TAP_DURATION_MS, false)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    /** Right-click equivalent: a sustained press. */
    private fun longPress(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y); lineTo(x, y) }
        val stroke = StrokeDescription(path, 0, LONG_PRESS_DURATION_MS, false)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    /** Drag step: move the pointer from one point to another. */
    private fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long) {
        if (x1 == x2 && y1 == y2) return
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        val stroke = StrokeDescription(path, 0, durationMs, false)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    /** Approximate a mouse wheel with a swipe; direction follows delta sign. */
    private fun scrollScreen(down: Boolean) {
        val h = resources.displayMetrics.heightPixels.toFloat()
        val w = resources.displayMetrics.widthPixels.toFloat()
        val cx = w / 2f
        val from = if (down) h * 0.70f else h * 0.30f
        val to = if (down) h * 0.30f else h * 0.70f
        swipe(cx, from, cx, to, SCROLL_DURATION_MS)
    }
}
