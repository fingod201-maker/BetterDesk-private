package com.carriez.flutter_hbb

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AgentRelayBridge - native (Rust FFI) dial-out relay client.
 *
 * Registers this device with the BetterDesk server (device enrollment) and
 * then connects OUT to the panel remote relay (WS /ws/remote-agent/<device_id>)
 * so operators can reach the phone over the internet through panel.telcom.stream.
 *
 * The FFI surface lives in flutter/src/lib.rs (JNI exports). Registration is
 * done here in Kotlin over HTTPS; the Rust side handles the WebSocket session,
 * start/stop control frames and the JPEG frame pump.
 */
object AgentRelayBridge {

    private const val TAG = "AgentRelayBridge"

    @Volatile
    private var loaded = false

    init {
        try {
            System.loadLibrary("betterdesk_flutter_android")
            loaded = true
        } catch (t: Throwable) {
            Log.e(TAG, "native library not available: ${t.message}")
        }
    }

    private fun ready(): Boolean = loaded

    // ── native FFI ────────────────────────────────────────────────────────

    private external fun nativeSetAgentConfig(deviceId: String, baseUrl: String, token: String)
    private external fun nativeConnect()
    private external fun nativeDisconnect()
    private external fun nativeIsStreaming(): Boolean
    private external fun nativeFeedFrame(frame: ByteArray): Boolean
    private external fun nativePopEvent(): String

    // ── Kotlin-facing API ─────────────────────────────────────────────────

    /** True when the operator session is live and frames are being consumed. */
    fun streaming(): Boolean = ready() && runCatching { nativeIsStreaming() }.getOrDefault(false)

    /** Push one JPEG frame to the relay. Returns false when not streaming. */
    fun feed(frameBytes: ByteArray): Boolean =
        ready() && runCatching { nativeFeedFrame(frameBytes) }.getOrDefault(false)

    /** Pop one pending input event (JSON) for the accessibility dispatcher. */
    fun popEvent(): String? {
        if (!loaded) return null
        val json = runCatching { nativePopEvent() }.getOrDefault("")
        return json.takeIf { it.isNotBlank() }
    }

    fun disconnect() {
        if (loaded) runCatching { nativeDisconnect() }
    }

    private val dialerStarted = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "AgentRelayBridge-reg").apply { isDaemon = true }
    }

    /**
     * Register the device and start the outbound relay dialer. Call once when
     * the unattended foreground service is running.
     */
    fun start(context: Context) {
        if (!ready() || !dialerStarted.compareAndSet(false, true)) return

        val config = resolvePanelConfig(context)
        executor.execute {
            try {
                val deviceId = Settings.Secure.getString(
                    context.contentResolver, Settings.Secure.ANDROID_ID
                )?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString().replace("-", "")

                val token = registerAndEnroll(config, deviceId)
                if (token != null) {
                    nativeSetAgentConfig(deviceId, config.baseUrl, token)
                    nativeConnect()
                    Log.i(TAG, "agent dialer connected (config=$config)")
                } else {
                    Log.w(TAG, "registration did not yield a device token; retry on next start")
                    dialerStarted.set(false)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "agent dialer start failed: ${t.message}")
                dialerStarted.set(false)
            }
        }
    }

    fun stop() {
        disconnect()
        dialerStarted.set(false)
    }

    // ── config resolution ─────────────────────────────────────────────────

    data class PanelConfig(val baseUrl: String)

    private fun resolvePanelConfig(context: Context): PanelConfig {
        val res = context.resources
        fun bakedString(name: String): String? {
            val rid = res.getIdentifier(name, "string", context.packageName)
            return if (rid != 0) res.getString(rid) else null
        }
        val host = bakedString("betterdesk_server_host")?.takeIf { it.isNotBlank() }
            ?: "panel.telcom.stream"
        val https = (bakedString("betterdesk_use_https") ?: "true")
            .let { !(it.equals("false", true) || it.equals("n", true) || it.equals("0")) }
        val scheme = if (https) "https" else "http"
        // Only bake a port when it is NOT the scheme default — Go server and
        // cloudflared deployments use 443, desktop tooling may use a custom port.
        val bakedPort = (bakedString("betterdesk_server_port")
            ?: bakedString("betterdesk_operator_port"))?.trim()?.toIntOrNull() ?: 0
        val hostWithPort: String =
            if (bakedPort !in intArrayOf(0, 80, 443) && !host.contains(":")) "$host:$bakedPort" else host
        return PanelConfig("$scheme://$hostWithPort")
    }

    // ── enrollment (mirrors the Go support agent) ─────────────────────────

    data class HttpResult(val code: Int, val body: JSONObject?)

    private fun getApi(apiBase: String, path: String): HttpResult {
        val conn = (URL(apiBase + path).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 10_000
            readTimeout = 10_000
        }
        return invoke(conn, null)
    }

    private fun invoke(conn: HttpURLConnection, bodyBytes: ByteArray?): HttpResult {
        try {
            bodyBytes?.let { bytes ->
                conn.outputStream.use { os -> os.write(bytes) }
            }
            val code = conn.responseCode
            val stream = if (code / 100 == 2) conn.inputStream else conn.errorStream
            var payload: JSONObject? = null
            try {
                stream?.let {
                    BufferedReader(InputStreamReader(it)).use { br ->
                        payload = JSONObject(br.readText())
                    }
                }
            } catch (_: Exception) {
            }
            return HttpResult(code, payload)
        } finally {
            conn.disconnect()
        }
    }

    private fun registerAndEnroll(config: PanelConfig, deviceId: String): String? {
        val apiBase = config.baseUrl.trimEnd('/') + "/api"
        val payload = JSONObject().apply {
            put("device_id", deviceId)
            put("uuid", deviceId)
            put("hostname", ((Build.MANUFACTURER ?: "unknown").ifBlank { "unknown" } +
                " " + (Build.MODEL ?: "device").ifBlank { "" }).trim())
            put(
                "platform",
                ("Android " + Build.VERSION.RELEASE + " " +
                    (Build.SUPPORTED_ABIS.firstOrNull() ?: "")).trim()
            )
            put(
                "version",
                ("Android " + Build.VERSION.RELEASE + " (SDK " + Build.VERSION.SDK_INT + ")")
            )
            put("device_type", "os_agent")
            put("bundle_id", "com.betterdesk.agent")
            put("tags", JSONArray().put("support-agent").put("android").put("fleet"))
        }

        val maxAttempts = 15
        var attempt = 0
        while (attempt < maxAttempts) {
            attempt++
            val result = try {
                val conn = (URL("$apiBase/devices/register").openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 10_000
                    readTimeout = 10_000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                }
                invoke(conn, payload.toString().toByteArray())
            } catch (t: Throwable) {
                Log.w(TAG, "register attempt $attempt failed: ${t.message}")
                return null
            }

            if (result.body == null || (result.code != 200 && result.code != 202)) {
                Log.w(TAG, "register HTTP ${result.code}")
                return null
            }
            when (result.body!!.optString("status")) {
                "approved" -> return result.body!!.optString("device_token").takeIf { it.isNotBlank() }
                "pending" -> {
                    Log.i(TAG, "device pending approval (attempt $attempt)")
                    Thread.sleep(5_000)
                }
                "rejected" -> {
                    Log.w(TAG, "device registration rejected by server")
                    return null
                }
                else -> return null
            }
        }
        return null
    }
}
