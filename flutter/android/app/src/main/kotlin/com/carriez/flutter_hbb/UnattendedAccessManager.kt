package com.carriez.flutter_hbb

import android.content.Context
import android.content.SharedPreferences
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

/**
 * UnattendedAccessManager — singleton that manages the unattended-access
 * session: permanent password, incoming connection listener, and method
 * channel bridge to Flutter.
 *
 * This is initialized once when the foreground service starts and lives
 * for the lifetime of the service.
 */
object UnattendedAccessManager {

    private const val TAG = "UnattendedAccessManager"
    private const val PREFS_NAME = "betterdesk_unattended"
    private const val KEY_PERMANENT_PASSWORD_HASH = "permanent_password_hash"
    private const val KEY_PASSWORD_SALT = "password_salt"
    private const val KEY_UNATTENDED_ENABLED = "unattended_enabled"

    private var methodChannel: MethodChannel? = null
    private var appContext: Context? = null
    private var isEnabled = false
    private var permanentPasswordHash: String? = null
    private var operatorHost: String = ""
    private var operatorPort: Int = 21122
    private var cdapUrl: String = ""
    private var consoleUrl: String = ""
    private var useHttps: Boolean = true
    private var apiHost: String = ""

    private val random = SecureRandom()

    /**
     * Initialize the manager. Called from the foreground service onCreate.
     */
    fun init(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isEnabled = prefs.getBoolean(KEY_UNATTENDED_ENABLED, false)
        // Migrate any legacy plaintext hash into the Keystore-backed store.
        permanentPasswordHash = readSecret(context, prefs, KEY_PERMANENT_PASSWORD_HASH)

        // Resource values baked at CI build time are the source of truth for
        // the operator endpoint; assets/config.json only fills the gaps.
        applyBakedConfig(context)
        loadEmbeddedConfig(context)

        methodChannel = MethodChannel(messenger, "betterdesk/unattended")
        methodChannel?.setMethodCallHandler(object : MethodCallHandler {
            override fun onMethodCall(call: MethodCall, result: Result) {
                when (call.method) {
                    "isUnattendedEnabled" -> result.success(isEnabled)
                    "setPermanentPassword" -> {
                        val password = call.arguments as? String ?: ""
                        setPermanentPassword(password, prefs)
                        result.success(null)
                    }
                    "setEmbeddedConfig" -> {
                        val args = call.arguments as? Map<String, *> ?: emptyMap<String, Any>()
                        val host = args["host"] as? String ?: ""
                        val port = (args["port"] as? Int) ?: 21122
                        val passwordHash = args["passwordHash"] as? String ?: ""
                        val cdapUrl = args["cdapUrl"] as? String ?: ""
                        val consoleUrl = args["consoleUrl"] as? String ?: ""
                        setEmbeddedConfig(host, port, passwordHash, prefs, args["cdapUrl"] as? String ?: "", args["consoleUrl"] as? String ?: "")
                        result.success(null)
                    }
                    "getConnectionInfo" -> {
                        result.success(mapOf(
                            "enabled" to isEnabled,
                            "hasPassword" to (permanentPasswordHash != null),
                            "operatorHost" to operatorHost,
                            "operatorPort" to operatorPort,
                            "useHttps" to useHttps,
                            "apiHost" to apiHost,
                            "cdapUrl" to cdapUrl,
                            "consoleUrl" to consoleUrl
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
        })
    }

    /**
     * Set embedded operator config from build-time bake-in.
     */
    private fun setEmbeddedConfig(
        host: String,
        port: Int,
        passwordHash: String,
        prefs: SharedPreferences,
        cdapUrl: String = "",
        consoleUrl: String = ""
    ) {
        operatorHost = host
        operatorPort = port
        this.cdapUrl = cdapUrl
        this.consoleUrl = consoleUrl
        if (passwordHash.isNotEmpty()) {
            permanentPasswordHash = passwordHash
            isEnabled = true
            writeSecret(prefs, KEY_PERMANENT_PASSWORD_HASH, passwordHash)
            prefs.edit()
                .putBoolean(KEY_UNATTENDED_ENABLED, true)
                .apply()
        }
    }

    fun dispose() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
    }

    /**
     * Set the permanent unattended-access password. The password is hashed
     * (PBKDF2 with a random salt) and stored — never in plaintext.
     */
    private fun setPermanentPassword(password: String, prefs: SharedPreferences) {
        if (password.isEmpty()) {
            isEnabled = false
            permanentPasswordHash = null
            appContext?.let {
                SecureCredentialStore.remove(it, KEY_PERMANENT_PASSWORD_HASH)
                SecureCredentialStore.remove(it, KEY_PASSWORD_SALT)
            }
            prefs.edit()
                .putBoolean(KEY_UNATTENDED_ENABLED, false)
                .remove(KEY_PERMANENT_PASSWORD_HASH)
                .remove(KEY_PASSWORD_SALT)
                .apply()
            return
        }

        val salt = generateSalt()
        val hash = deriveKey(password, salt)
        permanentPasswordHash = hash
        isEnabled = true

        writeSecret(prefs, KEY_PERMANENT_PASSWORD_HASH, hash)
        writeSecret(prefs, KEY_PASSWORD_SALT, salt)
        prefs.edit()
            .putBoolean(KEY_UNATTENDED_ENABLED, true)
            .apply()
    }

    /**
     * Verify a candidate password against the stored hash.
     */
    fun verifyPassword(candidate: String, context: Context): Boolean {
        if (!isEnabled || permanentPasswordHash == null) return false
        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val salt = readSecret(context, prefs, KEY_PASSWORD_SALT) ?: ""
        return deriveKey(candidate, salt) == permanentPasswordHash
    }

    // ---- Keystore-backed secret helpers ----

    /**
     * Read a credential from the Keystore-backed store, migrating a legacy
     * plaintext preference on first use so upgrades keep working.
     */
    private fun readSecret(
        context: Context,
        prefs: SharedPreferences,
        key: String
    ): String? {
        SecureCredentialStore.get(context, key)?.let { return it }
        val legacy = prefs.getString(key, null) ?: return null
        SecureCredentialStore.put(context, key, legacy)
        prefs.edit().remove(key).apply()
        return legacy
    }

    /** Encrypt and persist a credential, removing any plaintext legacy copy. */
    private fun writeSecret(prefs: SharedPreferences, key: String, value: String) {
        val ctx = appContext ?: return
        SecureCredentialStore.put(ctx, key, value)
        prefs.edit().remove(key).apply()
    }

    fun isEnabled(): Boolean = isEnabled

    /** True when the build is operator-managed (baked endpoint) or enabled. */
    fun isConfigured(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_UNATTENDED_ENABLED, false)) return true
        val resources = context.resources
        val id = resources.getIdentifier(
            "betterdesk_server_host", "string", context.packageName
        )
        return id != 0 && resources.getString(id).isNotBlank()
    }

    /**
     * Apply the operator endpoint baked into Android string resources at CI
     * build time. Ensures the unattended service knows where to enroll even
     * when the Flutter layer was built without dart-defines.
     */
    private fun applyBakedConfig(context: Context) {
        val res = context.resources
        fun baked(name: String): String? {
            val id = res.getIdentifier(name, "string", context.packageName)
            return if (id != 0) res.getString(id).trim() else null
        }

        val host = baked("betterdesk_server_host")?.takeIf { it.isNotBlank() } ?: return
        useHttps = (baked("betterdesk_use_https") ?: "true")
            .let { !(it.equals("false", true) || it == "0" || it.equals("n", true)) }
        val port = (baked("betterdesk_server_port")
            ?: baked("betterdesk_operator_port"))?.toIntOrNull() ?: 0

        operatorHost = host
        operatorPort = when {
            port > 0 -> port
            useHttps -> 443
            else -> 80
        }
        apiHost = baked("betterdesk_api_host") ?: ""

        if (!isEnabled) {
            isEnabled = true
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_UNATTENDED_ENABLED, true).apply()
        }
    }

    /**
     * Load embedded config from assets/config.json if available.
     */
    private fun loadEmbeddedConfig(context: Context): Boolean {
        return try {
            val inputStream = context.assets.open("config.json")
            val json = inputStream.bufferedReader().use { it.readText() }
            val jsonObject = org.json.JSONObject(json)

            // Never clobber the CI-baked endpoint with an empty asset value.
            val jsonHost = jsonObject.optString("server_address", "").trim()
            if (jsonHost.isNotBlank() && operatorHost.isBlank()) {
                operatorHost = jsonHost
            }
            val jsonPort = jsonObject.optInt("cdap_port", 0)
            if (jsonPort > 0 && operatorPort == 21122) {
                operatorPort = jsonPort
            }
            cdapUrl = jsonObject.optString("cdap_url", "")
            consoleUrl = jsonObject.optString("console_url", "")
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun generateSalt(): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun deriveKey(password: String, salt: String): String {
        val spec = javax.crypto.spec.PBEKeySpec(
            password.toCharArray(),
            salt.toByteArray(Charsets.UTF_8),
            100_000, 256
        )
        val factory = javax.crypto.SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val key = factory.generateSecret(spec).encoded
        return key.joinToString("") { "%02x".format(it) }
    }
}
