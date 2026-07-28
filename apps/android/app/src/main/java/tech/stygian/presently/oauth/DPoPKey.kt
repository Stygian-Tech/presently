package tech.stygian.presently.oauth

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.math.BigInteger
import java.net.URI
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.UUID

class DPoPKey private constructor(
    val id: String,
    private val keyPair: KeyPair,
) {
    fun proof(
        method: String,
        url: String,
        nonce: String?,
        accessToken: String? = null,
        nowEpochSeconds: Long = System.currentTimeMillis() / 1_000,
        identifier: String = UUID.randomUUID().toString(),
    ): String {
        val publicKey = keyPair.public as ECPublicKey
        val header = JSONObject().apply {
            put("typ", "dpop+jwt")
            put("alg", "ES256")
            put(
                "jwk",
                JSONObject().apply {
                    put("kty", "EC")
                    put("crv", "P-256")
                    put("x", publicKey.w.affineX.toUnsignedBytes(32).base64Url())
                    put("y", publicKey.w.affineY.toUnsignedBytes(32).base64Url())
                },
            )
        }
        val claims = JSONObject().apply {
            put("jti", identifier)
            put("htm", method.uppercase())
            put("htu", normalizeHtu(url))
            put("iat", nowEpochSeconds)
            nonce?.let { put("nonce", it) }
            accessToken?.let {
                put(
                    "ath",
                    MessageDigest.getInstance("SHA-256")
                        .digest(it.toByteArray(Charsets.UTF_8))
                        .base64Url(),
                )
            }
        }
        val signingInput = "${header.toString().toByteArray().base64Url()}." +
            claims.toString().toByteArray().base64Url()
        val derSignature = Signature.getInstance("SHA256withECDSA").run {
            initSign(keyPair.private)
            update(signingInput.toByteArray(Charsets.UTF_8))
            sign()
        }
        return "$signingInput.${derToJose(derSignature).base64Url()}"
    }

    fun delete() {
        KeyStore.getInstance(AndroidKeyStore).apply {
            load(null)
            deleteEntry(alias(id))
        }
    }

    companion object {
        private const val AndroidKeyStore = "AndroidKeyStore"

        fun create(): DPoPKey {
            val id = UUID.randomUUID().toString()
            val generator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_EC,
                AndroidKeyStore,
            )
            generator.initialize(
                KeyGenParameterSpec.Builder(
                    alias(id),
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            return DPoPKey(id, generator.generateKeyPair())
        }

        fun load(id: String): DPoPKey {
            val keyStore = KeyStore.getInstance(AndroidKeyStore).apply { load(null) }
            val privateKey = keyStore.getKey(alias(id), null)
                ?: throw OAuthException("This OAuth session's DPoP key is missing.")
            val publicKey = keyStore.getCertificate(alias(id))?.publicKey
                ?: throw OAuthException("This OAuth session's DPoP key is missing.")
            return DPoPKey(id, KeyPair(publicKey, privateKey as java.security.PrivateKey))
        }

        private fun alias(id: String) = "presently.oauth.dpop.$id"

        private fun normalizeHtu(value: String): String {
            val uri = URI(value)
            return URI(uri.scheme, uri.authority, uri.path, null, null).toString()
        }

        internal fun derToJose(der: ByteArray): ByteArray {
            var index = 0
            require(der[index++].toInt() == 0x30)
            index += encodedLengthBytes(der, index)
            require(der[index++].toInt() == 0x02)
            val rLengthInfo = readLength(der, index)
            index = rLengthInfo.next
            val r = der.copyOfRange(index, index + rLengthInfo.length)
            index += rLengthInfo.length
            require(der[index++].toInt() == 0x02)
            val sLengthInfo = readLength(der, index)
            index = sLengthInfo.next
            val s = der.copyOfRange(index, index + sLengthInfo.length)
            return r.toFixedInteger(32) + s.toFixedInteger(32)
        }

        private data class LengthInfo(val length: Int, val next: Int)

        private fun readLength(bytes: ByteArray, start: Int): LengthInfo {
            val first = bytes[start].toInt() and 0xff
            if (first < 0x80) return LengthInfo(first, start + 1)
            val count = first and 0x7f
            var value = 0
            repeat(count) { offset ->
                value = (value shl 8) or (bytes[start + 1 + offset].toInt() and 0xff)
            }
            return LengthInfo(value, start + 1 + count)
        }

        private fun encodedLengthBytes(bytes: ByteArray, start: Int): Int {
            val first = bytes[start].toInt() and 0xff
            return if (first < 0x80) 1 else 1 + (first and 0x7f)
        }

        private fun ByteArray.toFixedInteger(size: Int): ByteArray {
            val unsigned = dropWhile { it == 0.toByte() }.toByteArray()
            require(unsigned.size <= size)
            return ByteArray(size - unsigned.size) + unsigned
        }

        private fun BigInteger.toUnsignedBytes(size: Int): ByteArray =
            toByteArray().let { bytes ->
                val unsigned = bytes.dropWhile { it == 0.toByte() }.toByteArray()
                require(unsigned.size <= size)
                ByteArray(size - unsigned.size) + unsigned
            }

        private fun ByteArray.base64Url(): String = Base64.encodeToString(
            this,
            Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
        )
    }
}
