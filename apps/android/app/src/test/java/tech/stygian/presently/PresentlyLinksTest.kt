package tech.stygian.presently

import java.net.URI
import org.junit.Assert.assertEquals
import org.junit.Test

class PresentlyLinksTest {
    @Test
    fun feedbackBoardUsesTheCanonicalPresentlyBoard() {
        val uri = URI(PresentlyLinks.FeedbackBoard)

        assertEquals("https", uri.scheme)
        assertEquals("userinput.app", uri.host)
        assertEquals(
            "/s/did:plc:qy5pluw2bsuq2x6albsgkvx3/3msgekt2gyt2p",
            uri.path,
        )
    }

    @Test
    fun privacyPolicyUsesTheCanonicalPresentlyPage() {
        assertPresentlyPage(PresentlyLinks.PrivacyPolicy, "/privacy/")
    }

    @Test
    fun termsUseTheCanonicalPresentlyPage() {
        assertPresentlyPage(PresentlyLinks.Terms, "/terms/")
    }

    @Test
    fun supportUsesTheCanonicalPresentlyPage() {
        assertPresentlyPage(PresentlyLinks.Support, "/support/")
    }

    private fun assertPresentlyPage(url: String, expectedPath: String) {
        val uri = URI(url)

        assertEquals("https", uri.scheme)
        assertEquals("presently.photo", uri.host)
        assertEquals(expectedPath, uri.path)
    }
}
