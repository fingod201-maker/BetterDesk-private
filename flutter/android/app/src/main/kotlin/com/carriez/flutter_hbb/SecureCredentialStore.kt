package com.carriez.flutter_hbb

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * SecureCredentialStore — encrypts sensitive credentials with the Android
 * Keystore before they touch SharedPreferences.
 *
 * The enrollment Ed25519 seed and the per-device relay token are the two
 * secrets that let this installation authenticate to the operator server.
 * Storing them as plaintext preferences would let anyone with a backup,
 * root shell or a debugging build lift the identity. Instead the value is
 * encrypted with an AES-256-GCM key that never leaves the Keystore (hardware
 * backed where the device provides a TEE/StrongBox).
 *
 * Stored format: base64( 12-byte IV || AES-GCM ciphertext+tag ).
 *
 * API 23+ uses an AES/GCM Keystore key. API 22 (the app's minSdk) has no
 * Keystore AES support, so the value is stored base64-encoded with a warning;
 * that platform is only used for legacy testing hardware.
 */
object SecureCredentialStore {

    private const val TAG = "SecureCredentialStore"
    private const val PREFS_NAME = "betterdesk_secure"
    private const val KEY_ALIAS = "betterdesk_credentials_v1"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_BITS = 128
    private const val IV_BYTES = 12

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Encrypt and persist [value] under [key]. Returns true when the value was
     * written. On Keystore failure the value is not stored (callers regenerate
     * an identity rather than leaking the secret in the clear).
     */
    fun put(context: Context, key: String, value: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // Legacy fallback: no AES Keystore below API 23.
            Log.w(TAG, "Keystore AES unavailable on SDK ${Build.VERSION.SDK_INT}; storing obfuscated")
            return prefs(context).edit()
                .putString(key, "plain:" + Base64.encodeToString(value.toByteArray(Charsets.UTF_8), Base64.NO_WRAP))
                .commit()
        }
        return try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val iv = cipher.iv
            val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            val combined = ByteArray(iv.size + ciphertext.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)
            val encoded = Base64.encodeToString(combined, Base64.NO_WRAP)
            prefs(context).edit().putString(key, encoded).commit()
        } catch (t: Throwable) {
            Log.e(TAG, "secure put failed for '$key': ${t.javaClass.simpleName}: ${t.message}")
            false
        }
    }

    /** Decrypt [key]; returns null when absent or unreadable. */
    fun get(context: Context, key: String): String? {
        val stored = prefs(context).getString(key, null) ?: return null
        if (stored.startsWith("plain:")) {
            return try {
                String(Base64.decode(stored.removePrefix("plain:"), Base64.NO_WRAP), Charsets.UTF_8)
            } catch (_: Throwable) {
                null
            }
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        return try {
            val combined = Base64.decode(stored, Base64.NO_WRAP)
            if (combined.size <= IV_BYTES) return null
            val iv = combined.copyOfRange(0, IV_BYTES)
            val ciphertext = combined.copyOfRange(IV_BYTES, combined.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (t: Throwable) {
            // A re-generated Keystore key (factory reset / restore) invalidates
            // old ciphertext. Drop it so the caller can mint a fresh identity.
            Log.w(TAG, "secure get failed for '$key' (${t.javaClass.simpleName}); clearing")
            remove(context, key)
            null
        }
    }

    fun remove(context: Context, key: String) {
        prefs(context).edit().remove(key).apply()
    }

    /** True when the credential key is protected by a TEE / StrongBox. */
    fun isHardwareBacked(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            val secret = (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.secretKey
                ?: return false
            val factory = javax.crypto.SecretKeyFactory.getInstance(
                secret.algorithm, ANDROID_KEYSTORE
            )
            val info = factory.getKeySpec(secret, android.security.keystore.KeyInfo::class.java)
                as android.security.keystore.KeyInfo
            info.isInsideSecureHardware
        } catch (_: Throwable) {
            false
        }
    }

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (ks.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }
}
