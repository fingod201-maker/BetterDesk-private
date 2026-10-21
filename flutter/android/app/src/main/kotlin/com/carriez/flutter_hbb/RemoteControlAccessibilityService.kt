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
    private var lastStroke: StrokeDescription? = null
    private var pointerDown = false
    private var lastX = 0f
    private var lastY = 0f

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
     *   { "type": "wheel", "delta_y": ±1 }
     *   { "type": "key_down"|"key_up", "key": "Backspace|Back|Home|Escape" }
     * Coordinates from the browser viewer are canvas-relative [0..1].
     */
    fun dispatchJsonEvent(eventJson: String) {
        val obj = try { org.json.JSONObject(eventJson) } catch (e: org.json.JSONException) { return }
        val type = obj.optString("type")
        when (type) {
            "mouse_move" -> {
                val x = obj.optDouble("x", -1.0)
                val y = obj.optDouble("y", -1.0)
                if (x < 0 || y < 0) return
                lastX = (x * resources.displayMetrics.widthPixels).toFloat()
                lastY = (y * resources.displayMetrics.heightPixels).toFloat()
                if (pointerDown) continueStroke(lastX, lastY, up = false)
            }
            "mouse_down" -> {
                lastX = (obj.optDouble("x", 0.0) * resources.displayMetrics.widthPixels).toFloat()
                lastY = (obj.optDouble("y", 0.0) * resources.displayMetrics.heightPixels).toFloat()
                pointerDown = true
                beginStroke(lastX, lastY)
            }
            "mouse_up" -> {
                pointerDown = false
                continueStroke(lastX, lastY, up = true)
            }
            "wheel" -> {
                val dy = obj.optDouble("delta_y", 0.0)
                scrollScreen(dy > 0)
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

    /** Press-fresh stroke: first dispatchGesture, later events continue it. */
    private fun beginStroke(x: Float, y: Float) {
        val path = Path().apply { moveTo(x, y); lineTo(x, y) }
        val stroke = StrokeDescription(path, 0, 5, true)
        lastStroke = stroke
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private fun continueStroke(x: Float, y: Float, up: Boolean) {
        val prior = lastStroke ?: run {
            // No prior press (e.g. missed down): send a tap-like stroke.
            beginStroke(x, y)
            return
        }
        val path = Path().apply { moveTo(lastX, lastY); lineTo(x, y) }
        val next = prior.continueStroke(path, 0, 5, up)
        dispatchGesture(GestureDescription.Builder().addStroke(next).build(), null, null)
        lastX = x
        lastY = y
        if (up) lastStroke = null
    }

    /** Approximate a mouse wheel with a two-finger-free scroll swipe. */
    private fun scrollScreen(down: Boolean) {
        val w = resources.displayMetrics.widthPixels.toFloat()
        val h = resources.displayMetrics.heightPixels.toFloat()
        val cx = w / 2f
        val from = if (down) h * 0.70f else h * 0.30f
        val to = if (down) h * 0.30f else h * 0.70f
        val path = Path().apply { moveTo(cx, from); lineTo(cx, to) }
        val stroke = StrokeDescription(path, 0, 120, false)
        dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }
}
