package com.carriez.flutter_hbb

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * AgentRelayBridge - native (Rust FFI) dial-out relay client.
 *
 * Registers this device with the BetterDesk server (support-agent enrollment
 * with a signed installation proof) and then connects OUT to the panel remote
 * relay (WS /ws/remote-agent/<device_id>) so operators can reach the phone
 * over the internet through panel.telcom.stream.
 *
 * The FFI surface lives in flutter/src/lib.rs (JNI exports). The server
 * treats os_agent registrations as support-agent enrollments and requires:
 *   - uuid, bundle_id and an Ed25519 public_key in the body
 *   - X-BD-Enrollment-{Timestamp,Nonce,Signature} headers signing
 *     "bd-enrollment-v1\n<method>\n<path>\n<device_id>\n<pubkey>\n<ts>\n<nonce>"
 */
object AgentRelayBridge {

    private const val TAG = "AgentRelayBridge"
    private const val PREFS = "betterdesk_relay"
    private const val KEY_SEED = "enrollment_seed"
    private const val KEY_DEVICE_ID = "device_id"
    private const val KEY_TOKEN = "device_token"
    private const val BUNDLE_ID = "com.betterdesk.agent"
    private const val PATH_REGISTER = "/api/devices/register"
    private const val PATH_REGISTER_STATUS = "/api/devices/register/status"

    @Volatile
    private var loaded = false

    @Volatile
    private var stateValue: String = "idle"

    init {
        try {
            System.loadLibrary("betterdesk_flutter_android")
            loaded = true
        } catch (t: Throwable) {
            Log.e(TAG, "native library not available: ${t.message}")
        }
    }

    private fun ready(): Boolean = loaded

    /** Live dialer state for the UI: idle|starting|registering|connected|streaming. */
    fun state(): String = if (streaming()) "streaming" else stateValue

    /** Stable per-installation device id (BD-XXXXXXXXXXXX). */
    fun currentDeviceId(context: Context): String = deviceId(context.applicationContext)

    // ── native FFI ────────────────────────────────────────────────────────

    private external fun nativeSetAgentConfig(deviceId: String, baseUrl: String, token: String)
    private external fun nativeConnect()
    private external fun nativeDisconnect()
    private external fun nativeIsStreaming(): Boolean
    private external fun nativeFeedFrame(frame: ByteArray): Boolean
    private external fun nativePopEvent(): String
    private external fun nativeEnrollmentPublicKey(seed: String): String?
    private external fun nativeEnrollmentSign(seed: String, payload: String): String?

    // ── Kotlin-facing API ─────────────────────────────────────────────────

    /** True when the operator session is live and frames are being consumed. */
    fun streaming(): Boolean = ready() && runCatching { nativeIsStreaming() }.getOrDefault(false)

    @Volatile
    private var lastFeedAt = 0L

    /** Milliseconds since the last successfully fed frame (MAX_VALUE if none). */
    fun millisSinceLastFeed(): Long =
        if (lastFeedAt == 0L) Long.MAX_VALUE else System.currentTimeMillis() - lastFeedAt

    /** Push one JPEG frame to the relay. Returns false when not streaming. */
    fun feed(frameBytes: ByteArray): Boolean {
        val ok = ready() && runCatching { nativeFeedFrame(frameBytes) }.getOrDefault(false)
        if (ok) lastFeedAt = System.currentTimeMillis()
        return ok
    }

    /** Pop one pending input event (JSON) for the accessibility dispatcher. */
    fun popEvent(): String? {
        if (!loaded) return null
        val json = runCatching { nativePopEvent() }.getOrDefault("")
        return json.takeIf { it.isNotBlank() }
    }

    fun disconnect() {
        if (loaded) runCatching { nativeDisconnect() }
    }

    // ── capture geometry (JPEG frame size) ───────────────────────────────
    // The operator viewer sends coordinates in the frame's own pixel space
    // (or normalized 0..1). The dispatcher needs the capture size to map
    // frame pixels onto the real display resolution.

    @Volatile
    private var captureWidth: Int = 0

    @Volatile
    private var captureHeight: Int = 0

    fun noteCaptureSize(width: Int, height: Int) {
        if (width > 0 && height > 0) {
            captureWidth = width
            captureHeight = height
        }
    }

    fun captureSize(): Pair<Int, Int> = captureWidth to captureHeight

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
        stateValue = "starting"
        startEventPoller()

        val appContext = context.applicationContext
        val config = resolvePanelConfig(appContext)
        executor.execute {
            try {
                // A device removed from the panel can never enroll again under
                // the same id, so retry once with a fresh identity.
                var attempt = 0
                while (attempt < 2) {
                    attempt++
                    if (attempt > 1) {
                        if (!rotateDeviceId(appContext)) break
                        Log.i(TAG, "enrollment rejected for previous id - retrying with a new identity")
                    }
                    val id = deviceId(appContext)
                    stateValue = "registering"
                    val token = registerAndEnroll(appContext, config, id)
                    if (token != null) {
                        prefs(appContext).edit().putString(KEY_TOKEN, token).apply()
                        nativeSetAgentConfig(id, config.baseUrl, token)
                        nativeConnect()
                        stateValue = "connected"
                        Log.i(TAG, "agent dialer connected (device=$id, config=$config)")
                        return@execute
                    }
                }
                Log.w(TAG, "registration did not yield a device token")
                stateValue = "failed"
                dialerStarted.set(false)
            } catch (t: Throwable) {
                Log.w(TAG, "agent dialer start failed: ${t.message}")
                stateValue = "failed"
                dialerStarted.set(false)
            }
        }
    }

    private val pollerStarted = AtomicBoolean(false)

    /**
     * Drain the native dialer event queue continuously and log what it
     * reports, so relay connection problems surface in logcat (the Rust side
     * only has stderr, which Android discards).
     */
    private fun startEventPoller() {
        if (!pollerStarted.compareAndSet(false, true)) return
        Thread({
            while (dialerStarted.get()) {
                val json = popEvent()
                if (json != null) Log.i(TAG, "dialer event: $json")
                else Thread.sleep(1_000)
            }
        }, "AgentRelayBridge-events").apply { isDaemon = true }.start()
    }

    fun stop() {
        disconnect()
        dialerStarted.set(false)
        stateValue = "idle"
    }

    // ── identity (installation key + device id) ────────────────────────────

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 32-byte Ed25519 seed, generated once per installation. */
    private fun enrollmentSeed(context: Context): String {
        val p = prefs(context)
        p.getString(KEY_SEED, null)?.let { if (it.isNotBlank()) return it }
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        p.edit().putString(KEY_SEED, b64).apply()
        return b64
    }

    /** Stable per-installation device id (BD-XXXXXXXXXXXX). */
    private fun deviceId(context: Context): String {
        val p = prefs(context)
        p.getString(KEY_DEVICE_ID, null)?.let { if (it.isNotBlank()) return it }
        val bytes = ByteArray(6)
        SecureRandom().nextBytes(bytes)
        val id = "BD-" + bytes.joinToString("") { "%02X".format(it) }
        p.edit().putString(KEY_DEVICE_ID, id).apply()
        return id
    }

    private fun rotateDeviceId(context: Context): Boolean {
        val p = prefs(context)
        p.edit().remove(KEY_DEVICE_ID).remove(KEY_TOKEN).apply()
        return true
    }

    private fun publicKey(context: Context): String? {
        if (!loaded) return null
        return runCatching { nativeEnrollmentPublicKey(enrollmentSeed(context)) }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
    }

    private fun isoTimestamp(): String {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        return fmt.format(Date())
    }

    private fun nonce(): String {
        val bytes = ByteArray(16)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /**
     * Build the enrollment proof headers for one request. The server verifies
     * the signature over the canonical payload, so the method and the path as
     * seen by the server must be signed verbatim.
     */
    private fun proofHeaders(
        context: Context,
        deviceId: String,
        method: String,
        path: String,
        publicKey: String
    ): Map<String, String> {
        val seed = enrollmentSeed(context)
        val timestamp = isoTimestamp()
        val nonce = nonce()
        val payload = listOf("bd-enrollment-v1", method, path, deviceId, publicKey, timestamp, nonce)
            .joinToString("\n")
        val signature = runCatching { nativeEnrollmentSign(seed, payload) }.getOrNull()
            ?.takeIf { it.isNotBlank() } ?: return emptyMap()
        return mapOf(
            "X-BD-Enrollment-Timestamp" to timestamp,
            "X-BD-Enrollment-Nonce" to nonce,
            "X-BD-Enrollment-Signature" to signature
        )
    }

    // ── config resolution ─────────────────────────────────────────────────

    data class PanelConfig(val baseUrl: String, val restUrl: String)

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
        // The Go REST API (enrollment) lives on api.<base-domain>: the panel
        // host proxies /api with middleware that mangles enrollment proofs.
        val apiHost = bakedString("betterdesk_api_host")?.takeIf { it.isNotBlank() }
            ?: host.removePrefix("www.").replaceFirst("panel.", "api.")
        val rest = "$scheme://$apiHost"
        return PanelConfig("$scheme://$hostWithPort", rest)
    }

    // ── enrollment ────────────────────────────────────────────────────────

    data class HttpResult(val code: Int, val body: JSONObject?)

    private fun invoke(
        conn: HttpURLConnection,
        bodyBytes: ByteArray?,
        headers: Map<String, String>
    ): HttpResult {
        try {
            bodyBytes?.let { bytes ->
                conn.outputStream.use { os -> os.write(bytes) }
            }
            val code = conn.responseCode
            val stream = if (code / 100 == 2) conn.inputStream else conn.errorStream
            var payload: JSONObject? = null
            var text = ""
            try {
                stream?.let {
                    BufferedReader(InputStreamReader(it)).use { br ->
                        text = br.readText()
                        payload = JSONObject(text)
                    }
                }
            } catch (_: Exception) {
            }
            val snippet = if (text.length > 200) text.take(200) + "..." else text
            Log.i(TAG, "http ${conn.requestMethod} ${conn.url} -> $code body=$snippet")
            return HttpResult(code, payload)
        } finally {
            conn.disconnect()
        }
    }

    private fun post(
        url: String,
        body: JSONObject,
        headers: Map<String, String> = emptyMap()
    ): HttpResult {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 15_000
            readTimeout = 15_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
        }
        return invoke(conn, body.toString().toByteArray(), headers)
    }

    private fun get(url: String, headers: Map<String, String> = emptyMap()): HttpResult {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 15_000
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
        }
        return invoke(conn, null, headers)
    }

    private fun registerAndEnroll(
        context: Context,
        config: PanelConfig,
        deviceId: String
    ): String? {
        val publicKey = publicKey(context) ?: run {
            Log.w(TAG, "no enrollment public key available")
            return null
        }
        // PATH_REGISTER already contains the leading "/api" segment.
        val apiBase = config.restUrl.trimEnd('/')
        val payload = JSONObject().apply {
            put("device_id", deviceId)
            put("uuid", Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
                ?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString())
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
            put("bundle_id", BUNDLE_ID)
            put("public_key", publicKey)
        }

        val registerHeaders = proofHeaders(context, deviceId, "POST", PATH_REGISTER, publicKey)
        val registered = post("$apiBase$PATH_REGISTER", payload, registerHeaders)
        Log.i(TAG, "register -> HTTP ${registered.code} ${registered.body?.optString("status")}")
        registered.body?.optString("device_token")?.takeIf { it.isNotBlank() }?.let { return it }

        when (registered.body?.optString("status")) {
            "rejected" -> {
                Log.w(TAG, "enrollment rejected: ${registered.body?.optString("message")}")
                return null
            }
            "pending" -> Unit
            else -> {
                if (registered.code >= 400) {
                    Log.w(TAG, "registration failed HTTP ${registered.code}")
                    return null
                }
            }
        }

        // Managed mode: wait for the operator/auto-approver, polling the
        // status endpoint with a fresh proof each time. The server-side
        // auto-approver runs on a ~2 min cadence, so cover a 5 min window.
        val statusHeaders = proofHeaders(context, deviceId, "GET", PATH_REGISTER_STATUS, publicKey)
        repeat(20) { attempt ->
            Thread.sleep(15_000)
            val status = get("$apiBase$PATH_REGISTER_STATUS?device_id=$deviceId", statusHeaders)
            val state = status.body?.optString("status")
            Log.i(TAG, "status poll ${attempt + 1} -> HTTP ${status.code} $state")
            status.body?.optString("device_token")?.takeIf { it.isNotBlank() }?.let { return it }
            if (state == "rejected") {
                Log.w(TAG, "enrollment rejected: ${status.body?.optString("message")}")
                return null
            }
        }
        return null
    }
}
