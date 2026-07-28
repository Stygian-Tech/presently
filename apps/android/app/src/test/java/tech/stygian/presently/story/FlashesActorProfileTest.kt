package tech.stygian.presently.story

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FlashesActorProfileTest {
    @Test
    fun createsCurrentFlashesActorDefaults() {
        val profile = FlashesActorProfileFactory.create(
            Instant.parse("2026-07-27T12:34:56Z"),
        )

        assertEquals("blue.flashes.actor.profile", profile.getString("\$type"))
        assertEquals("2026-07-27T12:34:56Z", profile.getString("createdAt"))
        assertTrue(profile.getBoolean("showFeeds"))
        assertFalse(profile.getBoolean("showLikes"))
        assertTrue(profile.getBoolean("showLists"))
        assertTrue(profile.getBoolean("showMedia"))
        assertEquals("grid", profile.getString("mediaLayout"))
        assertFalse(profile.getBoolean("enablePortfolio"))
        assertEquals("grid", profile.getString("portfolioLayout"))
        assertFalse(profile.getBoolean("allowRawDownload"))
    }
}
