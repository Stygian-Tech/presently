package tech.stygian.presently.data

import org.junit.Assert.assertEquals
import org.junit.Test

class LocalStoryDraftTest {
    @Test
    fun retryKeepsPublicationIdentity() {
        val failed = LocalStoryDraft(
            id = "draft",
            imageData = byteArrayOf(1, 2, 3),
            state = LocalStoryDraft.State.Failed.storageValue,
            lastError = "offline",
            recordKey = "3mexampletid",
        )

        val retry = failed.copy(
            state = LocalStoryDraft.State.Publishing.storageValue,
            lastError = null,
        )

        assertEquals("draft", retry.id)
        assertEquals("3mexampletid", retry.recordKey)
        assertEquals("publishing", retry.state)
    }
}
