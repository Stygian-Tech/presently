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
}
