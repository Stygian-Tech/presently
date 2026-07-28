package tech.stygian.presently.oauth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class OAuthHttpClientTest {
    @Test
    fun acceptsValidMetadataWithoutDependingOnHeaderRepresentation() {
        val metadata = OAuthHttpClient.decodeJsonMetadata(
            OAuthHttpResponse(
                statusCode = 200,
                body = """{"issuer":"https://auth.example"}""".toByteArray(),
                headers = emptyMap(),
            ),
        )

        assertEquals("https://auth.example", metadata.getString("issuer"))
    }

    @Test
    fun rejectsNonJsonMetadata() {
        assertThrows(OAuthException::class.java) {
            OAuthHttpClient.decodeJsonMetadata(
                OAuthHttpResponse(
                    statusCode = 200,
                    body = "not json".toByteArray(),
                    headers = emptyMap(),
                ),
            )
        }
    }
}
