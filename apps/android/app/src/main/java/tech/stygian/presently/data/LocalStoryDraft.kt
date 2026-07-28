package tech.stygian.presently.data

import androidx.room.Entity
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(tableName = "local_story_drafts")
data class LocalStoryDraft(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val imageData: ByteArray,
    val createdAtEpochMillis: Long = System.currentTimeMillis(),
    val state: String = State.Pending.storageValue,
    val lastError: String? = null,
    val publishedUri: String? = null,
    val publishedCid: String? = null,
    val recordKey: String? = null,
) {
    enum class State(val storageValue: String) {
        Pending("pending"),
        Publishing("publishing"),
        Failed("failed"),
        Published("published"),
    }
}
