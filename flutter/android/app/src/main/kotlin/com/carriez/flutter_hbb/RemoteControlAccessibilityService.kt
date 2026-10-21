package com.carriez.flutter_hbb

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.accessibilityservice.GestureDescription.StrokeDescription
import android.accessibilityservice.AccessibilityServiceInfo
import android.graphics.Path
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.util.Log

/**
 * RemoteControlAccessibilityService — an AccessibilityService that allows
 * an operator to inject touch gestures and key events into the device,
 * enabling full remote control.
 *
 * The user must manually enable this in Settings → Accessibility →
 * BetterDesk Remote Control (Android requires explicit user consent).
 */
class RemoteControlAccessibilityService : AccessibilityService() {

    private companion object {
        const val TAG = "RemoteControlAccessibilityService"
        const val TAP_DURATION_MS = 60L
        const val LONG_PRESS_DURATION_MS = 600L
        const val DRAG_DURATION_MS = 50L
        const val SCROLL_DURATION_MS = 120L
        const val DRAG_STEP_PX = 4f
    }

    override fun onServiceConnected() {
        Log.i(TAG, "RemoteControlAccessibilityService connected")
        val info = serviceInfo
        if (info != null) {
            info.flags = AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            serviceInfo = info
        }
        super.onServiceConnected()
        startInputPump()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Forward UI events to the operator's viewer (screen updates)
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
        return super.onUnbind(intent)
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
