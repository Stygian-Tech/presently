package tech.stygian.presently.oauth

import org.json.JSONObject
import java.net.URI
import java.net.URLEncoder

class OAuthDiscovery(private val http: OAuthHttpClient) {
    suspend fun discover(rawIdentifier: String): DiscoveryResult {
        val identifier = rawIdentifier.trim().removePrefix("@")
        if (identifier.isEmpty()) throw OAuthException("Enter a valid handle or DID.")

        val handle: String?
        val did: String
        if (identifier.startsWith("did:")) {
            handle = null
            did = identifier
        } else {
            if (!HandlePattern.matches(identifier)) {
                throw OAuthException("Enter a valid AT Protocol handle or DID.")
            }
            handle = identifier.lowercase()
            did = resolveHandle(handle)
        }

        val didDocument = resolveDid(did)
        if (didDocument.getString("id") != did) {
            throw OAuthException("The account's DID document could not be verified.")
        }
        if (handle != null) {
            val aliases = didDocument.optJSONArray("alsoKnownAs")
            val claimsHandle = aliases != null && (0 until aliases.length()).any {
                aliases.getString(it).equals("at://$handle", ignoreCase = true)
            }
            if (!claimsHandle) {
                throw OAuthException("The account's DID document does not claim that handle.")
            }
        }
        val pdsUrl = pdsOrigin(did, didDocument)

        val resource = http.getJson("$pdsUrl/.well-known/oauth-protected-resource")
        val servers = resource.optJSONArray("authorization_servers")
        if (servers == null || servers.length() != 1) {
            throw OAuthException("The PDS returned invalid OAuth resource metadata.")
        }
        val issuer = secureOrigin(servers.getString(0))
        val metadata = http.getJson("$issuer/.well-known/oauth-authorization-server")
        val server = validateServer(metadata, issuer)

        return DiscoveryResult(identifier, did, handle, pdsUrl, server)
    }

    suspend fun validateAccount(did: String, pdsUrl: String, issuer: String) {
        val document = resolveDid(did)
        if (document.getString("id") != did || pdsOrigin(did, document) != pdsUrl) {
            throw OAuthException("The authorized account does not match its PDS.")
        }
        val resource = http.getJson("$pdsUrl/.well-known/oauth-protected-resource")
        val servers = resource.optJSONArray("authorization_servers")
        if (servers == null || servers.length() != 1 ||
            secureOrigin(servers.getString(0)) != issuer
        ) {
            throw OAuthException("The authorized account does not match its OAuth server.")
        }
    }

    private suspend fun resolveHandle(handle: String): String {
        runCatching {
            val response = http.get("https://$handle/.well-known/atproto-did")
            if (response.statusCode == 200) {
                val did = String(response.body, Charsets.UTF_8).trim()
                if (did.startsWith("did:")) return did
            }
        }

        val name = URLEncoder.encode("_atproto.$handle", Charsets.UTF_8.name())
        val response = http.get(
            "https://cloudflare-dns.com/dns-query?name=$name&type=TXT",
            mapOf("Accept" to "application/dns-json"),
        )
        if (response.statusCode == 200) {
            val answers = JSONObject(String(response.body, Charsets.UTF_8))
                .optJSONArray("Answer")
            if (answers != null) {
                for (index in 0 until answers.length()) {
                    val value = answers.getJSONObject(index)
                        .optString("data")
                        .trim('"')
                    if (value.startsWith("did=")) {
                        return value.removePrefix("did=")
                    }
                }
            }
        }
        throw OAuthException("That handle could not be resolved.")
    }

    private suspend fun resolveDid(did: String): JSONObject {
        val url = when {
            did.startsWith("did:plc:") -> "https://plc.directory/$did"
            did.startsWith("did:web:") -> {
                val parts = did.removePrefix("did:web:").split(":")
                val host = java.net.URLDecoder.decode(
                    parts.first(),
                    Charsets.UTF_8.name(),
                )
                if (host.contains("/") || host.contains("@") || host.contains("\\")) {
                    throw OAuthException("The account's did:web identifier is invalid.")
                }
                if (parts.size == 1) {
                    "https://$host/.well-known/did.json"
                } else {
                    val path = parts.drop(1).joinToString("/") {
                        java.net.URLDecoder.decode(it, Charsets.UTF_8.name())
                    }
                    "https://$host/$path/did.json"
                }
            }
            else -> throw OAuthException("Presently supports did:plc and did:web accounts.")
        }
        return http.getJson(url)
    }

    private fun pdsOrigin(did: String, document: JSONObject): String {
        val services = document.optJSONArray("service")
            ?: throw OAuthException("The account does not declare an AT Protocol PDS.")
        for (index in 0 until services.length()) {
            val service = services.getJSONObject(index)
            val id = service.optString("id")
            if ((id == "#atproto_pds" || id == "$did#atproto_pds") &&
                service.optString("type") == "AtprotoPersonalDataServer"
            ) {
                return secureOrigin(service.getString("serviceEndpoint"))
            }
        }
        throw OAuthException("The account does not declare an AT Protocol PDS.")
    }

    private fun validateServer(value: JSONObject, expectedIssuer: String): AuthorizationServer {
        fun strings(name: String) = value.optJSONArray(name)?.strings().orEmpty()
        val issuer = value.optString("issuer")
        val authorizationEndpoint = value.optString("authorization_endpoint")
        val tokenEndpoint = value.optString("token_endpoint")
        val parEndpoint = value.optString("pushed_authorization_request_endpoint")
        val valid = issuer == expectedIssuer &&
            strings("response_types_supported").contains("code") &&
            strings("grant_types_supported").containsAll(
                listOf("authorization_code", "refresh_token"),
            ) &&
            strings("code_challenge_methods_supported").contains("S256") &&
            strings("token_endpoint_auth_methods_supported").contains("none") &&
            strings("scopes_supported").contains("atproto") &&
            value.optBoolean("authorization_response_iss_parameter_supported") &&
            value.optBoolean("require_pushed_authorization_requests") &&
            strings("dpop_signing_alg_values_supported").contains("ES256") &&
            value.optBoolean("client_id_metadata_document_supported") &&
            isSecureEndpoint(authorizationEndpoint) &&
            isSecureEndpoint(tokenEndpoint) &&
            isSecureEndpoint(parEndpoint)
        if (!valid) {
            throw OAuthException(
                "The authorization server does not meet AT Protocol OAuth requirements.",
            )
        }
        return AuthorizationServer(
            issuer,
            authorizationEndpoint,
            tokenEndpoint,
            parEndpoint,
        )
    }

    private fun secureOrigin(value: String): String {
        val uri = URI(value)
        if (uri.scheme != "https" || uri.host == null || uri.userInfo != null) {
            throw OAuthException("OAuth servers must use a secure HTTPS origin.")
        }
        return URI("https", null, uri.host, uri.port, null, null, null).toString()
    }

    private fun isSecureEndpoint(value: String): Boolean = runCatching {
        val uri = URI(value)
        uri.scheme == "https" && uri.host != null && uri.userInfo == null
    }.getOrDefault(false)

    companion object {
        private val HandlePattern = Regex(
            """(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$""",
        )
    }
}
