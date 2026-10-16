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
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_CAN_PERFORM_GESTURES or
                AccessibilityServiceInfo.FLAG_CAN_TAKE_SCREENSHOT or
                AccessibilityServiceInfo.FLAG_CAN_OBSERVE_GESTURES or
                AccessibilityServiceInfo.FLAG_CAN_CONTROL_RELATIVE_GESTURES
            serviceInfo = info
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Forward UI events to the operator's viewer (screen updates)
    }

    override fun onInterrupt() {
        Log.i(TAG, "RemoteControlAccessibilityService interrupted")
    }

    override fun onGesture(properties: GestureDescription?): Boolean {
        return super.onGesture(properties)
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
        val event = KeyEvent(if (down) KeyEvent.ACTION_DOWN else KeyEvent.ACTION_UP, keyCode)
        dispatchKeyEvent(event)
    }
}
