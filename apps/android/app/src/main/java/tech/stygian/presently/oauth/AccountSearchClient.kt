package tech.stygian.presently.oauth

import java.net.URLEncoder
import org.json.JSONObject

data class AccountSuggestion(
    val did: String,
    val handle: String,
    val displayName: String?,
    val avatarUrl: String?,
)

class AccountSearchClient(
    private val http: OAuthHttpClient = OAuthHttpClient(),
) {
    suspend fun search(query: String, limit: Int = 6): List<AccountSuggestion> {
        val normalized = query.trim().removePrefix("@")
        if (normalized.length < 2) return emptyList()
        val encoded = URLEncoder.encode(normalized, Charsets.UTF_8.name())
        val response = http.get(
            "$Endpoint?q=$encoded&limit=${limit.coerceIn(1, 10)}",
            mapOf("Accept" to "application/json"),
        )
        if (response.statusCode != 200) return emptyList()

        return parseResponse(String(response.body, Charsets.UTF_8))
    }

    companion object {
        const val Endpoint =
            "https://public.api.bsky.app/xrpc/app.bsky.actor.searchActorsTypeahead"

        internal fun parseResponse(body: String): List<AccountSuggestion> {
            val actors = JSONObject(body)
                .optJSONArray("actors") ?: return emptyList()
            return buildList {
                for (index in 0 until actors.length()) {
                    val actor = actors.optJSONObject(index) ?: continue
                    val did = actor.optString("did")
                    val handle = actor.optString("handle")
                    if (did.isBlank() || handle.isBlank()) continue
                    add(
                        AccountSuggestion(
                            did = did,
                            handle = handle,
                            displayName = actor.optionalString("displayName"),
                            avatarUrl = actor.optionalString("avatar"),
                        ),
                    )
                }
            }
        }
    }
}
