package tech.stygian.presently.oauth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder

data class OAuthHttpResponse(
    val statusCode: Int,
    val body: ByteArray,
    val headers: Map<String, List<String>>,
) {
    val dpopNonce: String?
        get() = headers.entries.firstOrNull {
            it.key.equals("DPoP-Nonce", ignoreCase = true)
        }?.value?.firstOrNull()
}

class OAuthHttpClient {
    suspend fun get(
        url: String,
        headers: Map<String, String> = emptyMap(),
    ): OAuthHttpResponse = request("GET", url, null, headers)

    suspend fun getJson(url: String): org.json.JSONObject {
        val response = get(url, mapOf("Accept" to "application/json"))
        return decodeJsonMetadata(response)
    }

    companion object {
        internal fun decodeJsonMetadata(
            response: OAuthHttpResponse,
        ): org.json.JSONObject {
            if (response.statusCode != 200) {
                throw OAuthException("The server returned invalid OAuth metadata.")
            }
            return runCatching {
                org.json.JSONObject(String(response.body, Charsets.UTF_8))
            }.getOrElse {
                throw OAuthException("The server returned invalid OAuth metadata.")
            }
        }
    }

    suspend fun postForm(
        url: String,
        fields: List<Pair<String, String>>,
        headers: Map<String, String>,
    ): OAuthHttpResponse {
        val form = fields.joinToString("&") { (name, value) ->
            "${name.formEncode()}=${value.formEncode()}"
        }.toByteArray(Charsets.UTF_8)
        return request(
            "POST",
            url,
            form,
            headers + mapOf(
                "Content-Type" to "application/x-www-form-urlencoded",
                "Accept" to "application/json",
            ),
        )
    }

    suspend fun post(
        url: String,
        body: ByteArray,
        contentType: String,
        headers: Map<String, String>,
    ): OAuthHttpResponse = request(
        "POST",
        url,
        body,
        headers + mapOf(
            "Content-Type" to contentType,
            "Accept" to "application/json",
        ),
    )

    suspend fun request(
        method: String,
        url: String,
        body: ByteArray?,
        headers: Map<String, String>,
    ): OAuthHttpResponse = withContext(Dispatchers.IO) {
        val uri = URI(url)
        require(uri.scheme == "https")
        val connection = uri.toURL().openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = false
        connection.requestMethod = method
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        for ((name, value) in headers) {
            connection.setRequestProperty(name, value)
        }
        if (body != null) {
            connection.doOutput = true
            connection.outputStream.use { it.write(body) }
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val response = OAuthHttpResponse(
            statusCode = status,
            body = stream?.use { it.readBytes() } ?: ByteArray(0),
            headers = connection.headerFields
                .filterKeys { it != null }
                .mapKeys { it.key!! },
        )
        connection.disconnect()
        response
    }

    private fun String.formEncode(): String =
        URLEncoder.encode(this, Charsets.UTF_8.name())
}
