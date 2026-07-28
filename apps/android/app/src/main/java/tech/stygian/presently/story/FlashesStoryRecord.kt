package tech.stygian.presently.story

import java.time.Instant
import java.security.SecureRandom
import org.json.JSONObject

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

fun ATProtoBlob.toJson(): JSONObject = JSONObject().apply {
    put("\$type", type)
    put("ref", JSONObject().put("\$link", cid))
    put("mimeType", mimeType)
    put("size", size)
}

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

fun FlashesStoryRecord.toJson(): JSONObject = JSONObject().apply {
    put("\$type", type)
    put("image", image.toJson())
    put("createdAt", createdAt)
    put("expiresInMinutes", expiresInMinutes)
}

data class PublishedStory(
    val uri: String,
    val cid: String?,
)

object ATProtoTid {
    private const val Alphabet = "234567abcdefghijklmnopqrstuvwxyz"
    private val random = SecureRandom()

    fun create(
        epochMillis: Long = System.currentTimeMillis(),
        clockIdentifier: Int = random.nextInt(1_024),
    ): String {
        var value = (epochMillis.coerceAtLeast(0) * 1_000L shl 10) or
            (clockIdentifier and 0x03ff).toLong()
        val characters = CharArray(13) { '2' }
        for (index in 12 downTo 0) {
            characters[index] = Alphabet[(value and 0x1f).toInt()]
            value = value ushr 5
        }
        return String(characters)
    }
}

class StoryPublishingException(message: String) : Exception(message)
