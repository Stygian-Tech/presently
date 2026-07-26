package tech.stygian.presently.story

import java.time.Instant

object FlashesStoryContract {
    const val Collection = "blue.flashes.story.post"
    const val ExpiresInMinutes = 1_440
    const val MaximumImageBytes = 10_485_760
    const val JpegMimeType = "image/jpeg"
}

data class ATProtoBlob(
    val type: String = "blob",
    val cid: String,
    val mimeType: String,
    val size: Int,
)

data class FlashesStoryRecord(
    val type: String,
    val image: ATProtoBlob,
    val createdAt: String,
    val expiresInMinutes: Int,
)

object FlashesStoryRecordFactory {
    fun create(blob: ATProtoBlob, createdAt: Instant): FlashesStoryRecord {
        require(blob.mimeType == FlashesStoryContract.JpegMimeType) {
            "Presently's MVP only publishes JPEG images."
        }
        require(blob.size <= FlashesStoryContract.MaximumImageBytes) {
            "Flashes stories allow images up to 10 MiB."
        }

        return FlashesStoryRecord(
            type = FlashesStoryContract.Collection,
            image = blob,
            createdAt = createdAt.toString(),
            expiresInMinutes = FlashesStoryContract.ExpiresInMinutes,
        )
    }
}
