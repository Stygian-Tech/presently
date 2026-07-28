package tech.stygian.presently.oauth

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OAuthContractTest {
    @Test
    fun requestsOnlyPresentlyMvpOperations() {
        assertEquals(
            listOf(
                "atproto",
                "repo:blue.flashes.actor.profile?action=create",
                "repo:blue.flashes.story.post?action=create",
                "blob:image/jpeg",
            ),
            OAuthConfig.Scopes,
        )
        assertEquals(
            "atproto repo:blue.flashes.actor.profile?action=create " +
                "repo:blue.flashes.story.post?action=create blob:image/jpeg",
            OAuthConfig.Scope,
        )
        assertFalse(OAuthConfig.Scope.contains("transition:generic"))
        assertFalse(OAuthConfig.Scope.contains("repo:*"))
        assertFalse(OAuthConfig.Scope.contains("blob:*/*"))
    }

    @Test
    fun convertsEcdsaDerSignatureToJoseCoordinates() {
        val r = ByteArray(32) { (it + 1).toByte() }
        val s = ByteArray(32) { (it + 33).toByte() }
        val der = byteArrayOf(0x30, 0x44, 0x02, 0x20) +
            r +
            byteArrayOf(0x02, 0x20) +
            s

        assertArrayEquals(r + s, DPoPKey.derToJose(der))
    }

    @Test
    fun publishingRequiresScopesAndCompletedActorSetup() {
        val base = OAuthSession(
            accountDid = "did:plc:example",
            handle = "sam.bsky.social",
            pdsUrl = "https://pds.example",
            issuer = "https://auth.example",
            tokenEndpoint = "https://auth.example/token",
            accessToken = "access",
            refreshToken = "refresh",
            scopes = OAuthConfig.Scopes,
            expiresAtEpochMillis = Long.MAX_VALUE,
            dpopKeyId = "key",
            authorizationServerNonce = null,
            resourceServerNonce = null,
            flashesActorProfileReady = false,
        )

        assertFalse(base.canPublishStory)
        assertTrue(base.copy(flashesActorProfileReady = true).canPublishStory)
    }
}
