package tech.stygian.presently.oauth

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureOAuthStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        "presently_oauth_secure",
        Context.MODE_PRIVATE,
    )

    fun loadSession(): OAuthSession? =
        read("session")?.let(::decodeSession)

    fun saveSession(session: OAuthSession) {
        write("session", encodeSession(session))
    }

    fun deleteSession() {
        preferences.edit().remove("session").apply()
    }

    fun loadPending(): PendingAuthorization? =
        read("pending")?.let(::decodePending)

    fun savePending(pending: PendingAuthorization) {
        write("pending", encodePending(pending))
    }

    fun deletePending() {
        preferences.edit().remove("pending").apply()
    }

    private fun write(name: String, value: JSONObject) {
        val cipher = Cipher.getInstance(Transformation)
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey())
        val encrypted = cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8))
        val combined = ByteArray(cipher.iv.size + encrypted.size)
        cipher.iv.copyInto(combined)
        encrypted.copyInto(combined, cipher.iv.size)
        preferences.edit()
            .putString(name, Base64.encodeToString(combined, Base64.NO_WRAP))
            .apply()
    }

    private fun read(name: String): JSONObject? {
        val encoded = preferences.getString(name, null) ?: return null
        return runCatching {
            val combined = Base64.decode(encoded, Base64.NO_WRAP)
            require(combined.size > IvBytes)
            val cipher = Cipher.getInstance(Transformation)
            cipher.init(
                Cipher.DECRYPT_MODE,
                encryptionKey(),
                GCMParameterSpec(128, combined.copyOfRange(0, IvBytes)),
            )
            val cleartext = cipher.doFinal(
                combined.copyOfRange(IvBytes, combined.size),
            )
            JSONObject(String(cleartext, Charsets.UTF_8))
        }.getOrNull()
    }

    private fun encryptionKey(): SecretKey {
        val keyStore = KeyStore.getInstance(AndroidKeyStore).apply { load(null) }
        (keyStore.getKey(EncryptionAlias, null) as? SecretKey)?.let { return it }

        return KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            AndroidKeyStore,
        ).apply {
            init(
                KeyGenParameterSpec.Builder(
                    EncryptionAlias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
        }.generateKey()
    }

    private fun encodeSession(value: OAuthSession) = JSONObject().apply {
        put("accountDid", value.accountDid)
        put("handle", value.handle)
        put("pdsUrl", value.pdsUrl)
        put("issuer", value.issuer)
        put("tokenEndpoint", value.tokenEndpoint)
        put("accessToken", value.accessToken)
        put("refreshToken", value.refreshToken)
        put("scopes", JSONArray(value.scopes))
        put("expiresAt", value.expiresAtEpochMillis)
        put("dpopKeyId", value.dpopKeyId)
        put("authNonce", value.authorizationServerNonce)
        put("resourceNonce", value.resourceServerNonce)
        put("flashesActorProfileReady", value.flashesActorProfileReady)
    }

    private fun decodeSession(value: JSONObject) = OAuthSession(
        accountDid = value.getString("accountDid"),
        handle = value.optionalString("handle"),
        pdsUrl = value.getString("pdsUrl"),
        issuer = value.getString("issuer"),
        tokenEndpoint = value.getString("tokenEndpoint"),
        accessToken = value.getString("accessToken"),
        refreshToken = value.getString("refreshToken"),
        scopes = value.getJSONArray("scopes").strings(),
        expiresAtEpochMillis = value.getLong("expiresAt"),
        dpopKeyId = value.getString("dpopKeyId"),
        authorizationServerNonce = value.optionalString("authNonce"),
        resourceServerNonce = value.optionalString("resourceNonce"),
        flashesActorProfileReady = if (value.isNull("flashesActorProfileReady")) {
            null
        } else {
            value.optBoolean("flashesActorProfileReady")
        },
    )

    private fun encodePending(value: PendingAuthorization) = JSONObject().apply {
        put("inputIdentifier", value.inputIdentifier)
        put("expectedDid", value.expectedDid)
        put("pdsUrl", value.pdsUrl)
        put("issuer", value.issuer)
        put("authorizationEndpoint", value.authorizationEndpoint)
        put("tokenEndpoint", value.tokenEndpoint)
        put("state", value.state)
        put("codeVerifier", value.codeVerifier)
        put("dpopKeyId", value.dpopKeyId)
        put("authNonce", value.authorizationServerNonce)
    }

    private fun decodePending(value: JSONObject) = PendingAuthorization(
        inputIdentifier = value.getString("inputIdentifier"),
        expectedDid = value.getString("expectedDid"),
        pdsUrl = value.getString("pdsUrl"),
        issuer = value.getString("issuer"),
        authorizationEndpoint = value.getString("authorizationEndpoint"),
        tokenEndpoint = value.getString("tokenEndpoint"),
        state = value.getString("state"),
        codeVerifier = value.getString("codeVerifier"),
        dpopKeyId = value.getString("dpopKeyId"),
        authorizationServerNonce = value.optionalString("authNonce"),
    )

    companion object {
        private const val AndroidKeyStore = "AndroidKeyStore"
        private const val EncryptionAlias = "presently.oauth.storage"
        private const val Transformation = "AES/GCM/NoPadding"
        private const val IvBytes = 12
    }
}

internal fun JSONObject.optionalString(name: String): String? =
    if (isNull(name)) null else optString(name).takeIf(String::isNotEmpty)

internal fun JSONArray.strings(): List<String> =
    (0 until length()).map(::getString)
