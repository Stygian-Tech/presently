package tech.stygian.presently.story

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class FlashesStoryRecordTest {
    @Test
    fun createsCurrentFlashesStoryShape() {
        val blob = ATProtoBlob(
            cid = "bafkreiexample",
            mimeType = "image/jpeg",
            size = 512_000,
        )

        val record = FlashesStoryRecordFactory.create(
            blob = blob,
            createdAt = Instant.parse("2026-07-26T02:00:00Z"),
        )

        assertEquals("blue.flashes.story.post", record.type)
        assertEquals("2026-07-26T02:00:00Z", record.createdAt)
        assertEquals(1_440, record.expiresInMinutes)
        assertEquals(blob, record.image)
    }

    @Test
    fun rejectsImagesOverPublishedLimit() {
        val blob = ATProtoBlob(
            cid = "bafkreiexample",
            mimeType = "image/jpeg",
            size = FlashesStoryContract.MaximumImageBytes + 1,
        )

        assertThrows(IllegalArgumentException::class.java) {
            FlashesStoryRecordFactory.create(blob, Instant.EPOCH)
        }
    }

    @Test
    fun rejectsNonJpegForMvp() {
        val blob = ATProtoBlob(
            cid = "bafkreiexample",
            mimeType = "image/png",
            size = 10,
        )

        assertThrows(IllegalArgumentException::class.java) {
            FlashesStoryRecordFactory.create(blob, Instant.EPOCH)
        }
    }
}
