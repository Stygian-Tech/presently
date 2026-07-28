package tech.stygian.presently.oauth

import org.junit.Assert.assertEquals
import org.junit.Test

class AccountSearchClientTest {
    @Test
    fun decodesFriendlyTypeaheadResultsAndSkipsInvalidActors() {
        val results = AccountSearchClient.parseResponse(
            """
            {
              "actors": [
                {
                  "did": "did:plc:example",
                  "handle": "sam.bsky.social",
                  "displayName": "Sam",
                  "avatar": "https://cdn.example/avatar.jpg"
                },
                {
                  "did": "",
                  "handle": "invalid.example"
                }
              ]
            }
            """.trimIndent(),
        )

        assertEquals(
            listOf(
                AccountSuggestion(
                    did = "did:plc:example",
                    handle = "sam.bsky.social",
                    displayName = "Sam",
                    avatarUrl = "https://cdn.example/avatar.jpg",
                ),
            ),
            results,
        )
    }
}
