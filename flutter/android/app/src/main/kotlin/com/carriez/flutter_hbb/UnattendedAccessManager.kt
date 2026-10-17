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
    private var isEnabled = false
    private var permanentPasswordHash: String? = null
    private var operatorHost: String = ""
    private var operatorPort: Int = 21122

    private val random = SecureRandom()

    /**
     * Initialize the manager. Called from the foreground service onCreate.
     */
    fun init(messenger: BinaryMessenger, context: Context) {
        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isEnabled = prefs.getBoolean(KEY_UNATTENDED_ENABLED, false)
        permanentPasswordHash = prefs.getString(KEY_PERMANENT_PASSWORD_HASH, null)

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
                        setEmbeddedConfig(host, port, passwordHash, prefs)
                        result.success(null)
                    }
                    "getConnectionInfo" -> {
                        result.success(mapOf(
                            "enabled" to isEnabled,
                            "hasPassword" to (permanentPasswordHash != null),
                            "operatorHost" to operatorHost,
                            "operatorPort" to operatorPort,
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
    private fun setEmbeddedConfig(host: String, port: Int, passwordHash: String, prefs: SharedPreferences) {
        operatorHost = host
        operatorPort = port
        if (passwordHash.isNotEmpty()) {
            permanentPasswordHash = passwordHash
            isEnabled = true
            prefs.edit()
                .putBoolean(KEY_UNATTENDED_ENABLED, true)
                .putString(KEY_PERMANENT_PASSWORD_HASH, passwordHash)
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

        prefs.edit()
            .putBoolean(KEY_UNATTENDED_ENABLED, true)
            .putString(KEY_PERMANENT_PASSWORD_HASH, hash)
            .putString(KEY_PASSWORD_SALT, salt)
            .apply()
    }

    /**
     * Verify a candidate password against the stored hash.
     */
    fun verifyPassword(candidate: String, context: Context): Boolean {
        if (!isEnabled || permanentPasswordHash == null) return false
        val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val salt = prefs.getString(KEY_PASSWORD_SALT, "") ?: ""
        return deriveKey(candidate, salt) == permanentPasswordHash
    }

    fun isEnabled(): Boolean = isEnabled

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
