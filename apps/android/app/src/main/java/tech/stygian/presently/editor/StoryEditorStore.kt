package tech.stygian.presently.editor

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.util.AtomicFile
import androidx.exifinterface.media.ExifInterface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import tech.stygian.presently.camera.JpegOrientationNormalizer
import tech.stygian.presently.data.LocalStoryDraft
import tech.stygian.presently.data.PresentlyDao
import tech.stygian.presently.story.ATProtoTid
import java.io.File
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.UUID

internal class StoryEditorStore(private val context: Context, private val dao: PresentlyDao) {
    private val mutex = Mutex()
    private val root = File(context.filesDir, "story-editor")
    private fun directory(id: String): File = File(root, id).also { it.mkdirs() }
    private fun original(draft: LocalStoryDraft): File = File(directory(draft.id), "original.jpg")
    private fun rendered(draft: LocalStoryDraft): File = File(directory(draft.id), "rendered.jpg")

    suspend fun restore(): LocalStoryDraft? = withContext(Dispatchers.IO) { dao.latestUnfinishedDraft() }

    suspend fun create(bytes: ByteArray): LocalStoryDraft = withContext(Dispatchers.IO) {
        mutex.withLock {
            val draft = LocalStoryDraft(imageData = byteArrayOf(), originalImagePath = "original.jpg", compositionJson = StoryComposition().encode())
            atomicWrite(original(draft), bytes)
            dao.upsertDraft(draft)
            draft
        }
    }

    suspend fun source(draft: LocalStoryDraft): ByteArray = withContext(Dispatchers.IO) {
        if (draft.originalImagePath != null) original(draft).readBytes() else draft.imageData
    }

    suspend fun save(draft: LocalStoryDraft, composition: StoryComposition): LocalStoryDraft = withContext(Dispatchers.IO) {
        mutex.withLock {
            check(draft.renderedImagePath == null && draft.recordKey == null) { "Posted attempts cannot be edited. Retry or discard this story." }
            draft.copy(compositionJson = composition.encode()).also { dao.upsertDraft(it) }
        }
    }

    suspend fun freeze(draft: LocalStoryDraft, composition: StoryComposition): Pair<LocalStoryDraft, ByteArray> = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (draft.renderedImagePath != null) return@withLock draft to rendered(draft).readBytes()
            // Existing pre-editor attempts also retain their exact original bytes and record key.
            val bytes = if (draft.recordKey != null && draft.compositionJson == null) draft.imageData else {
                val bitmap = decodeBounded(source(draft), 2048)
                val assets = loadAssets(draft, composition)
                try { StoryRenderer.render(bitmap, composition, assets) }
                finally { bitmap.recycle(); assets.values.forEach { it.recycle() } }
            }
            atomicWrite(rendered(draft), bytes)
            val frozen = draft.copy(
                compositionJson = composition.encode(), renderedImagePath = "rendered.jpg",
                recordKey = draft.recordKey ?: ATProtoTid.create(),
            )
            dao.upsertDraft(frozen)
            frozen to bytes
        }
    }

    suspend fun discard(draft: LocalStoryDraft) = withContext(Dispatchers.IO) {
        mutex.withLock { dao.deleteDraft(draft.id); directory(draft.id).deleteRecursively(); Unit }
    }

    suspend fun importSticker(draft: LocalStoryDraft, uri: Uri): String = withContext(Dispatchers.IO) {
        val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArrayOutputStream()
            val block = ByteArray(8192)
            while (true) {
                val size = input.read(block)
                if (size < 0) break
                require(buffer.size() + size <= 8 * 1024 * 1024) { "Choose a sticker smaller than 8 MiB." }
                buffer.write(block, 0, size)
            }
            buffer.toByteArray()
        } ?: error("This image could not be opened.")
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        require(options.outMimeType in listOf("image/png", "image/jpeg", "image/webp")) { "Choose a static PNG, JPEG, or WebP image." }
        require(!isAnimatedImage(bytes)) { "Animated stickers aren’t supported yet. Choose a still image." }
        val decoded = decodeBounded(bytes, 512)
        val orientation = runCatching { ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        val transform = JpegOrientationNormalizer.transformFor(orientation)
        val bitmap = if (transform.isIdentity) decoded else Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, Matrix().apply {
            setRotate(transform.rotationDegrees); postScale(transform.horizontalScale, transform.verticalScale)
        }, true)
        if (bitmap !== decoded) decoded.recycle()
        val name = "${UUID.randomUUID()}.png"
        try {
            val encoded = ByteArrayOutputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                output.toByteArray()
            }
            atomicWrite(File(directory(draft.id), name), encoded)
        } finally { bitmap.recycle() }
        name
    }

    suspend fun loadAssets(draft: LocalStoryDraft, composition: StoryComposition): Map<String, Bitmap> = withContext(Dispatchers.IO) {
        val loaded = mutableMapOf<String, Bitmap>()
        try {
            val names = composition.layers.mapNotNull { it.asset }.distinct()
            require(names.size <= 10) { "A story can have up to 10 image stickers." }
            names.forEach { name ->
                require(name.matches(Regex("[a-zA-Z0-9-]+\\.png")))
                loaded[name] = decodeBounded(File(directory(draft.id), name).readBytes(), 512)
            }
            loaded
        } catch (error: Throwable) {
            loaded.values.forEach { it.recycle() }
            throw error
        }
    }

    companion object {
        fun decodeBounded(bytes: ByteArray, maximumDimension: Int): Bitmap {
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
            require(options.outWidth in 1..32000 && options.outHeight in 1..32000) { "This image has unsupported dimensions." }
            options.inJustDecodeBounds = false
            options.inSampleSize = 1
            while (maxOf(options.outWidth, options.outHeight) / options.inSampleSize > maximumDimension) options.inSampleSize *= 2
            return requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)) { "This image could not be decoded." }
        }

        internal fun isAnimatedImage(bytes: ByteArray): Boolean {
            fun tag(offset: Int, value: String): Boolean = offset >= 0 && offset + value.length <= bytes.size &&
                value.indices.all { bytes[offset + it].toInt() and 255 == value[it].code }
            fun unsignedInt(offset: Int, littleEndian: Boolean): Long {
                if (offset + 4 > bytes.size) return -1
                return (0..3).fold(0L) { result, index ->
                    result or ((bytes[offset + index].toLong() and 255L) shl (if (littleEndian) index * 8 else (3 - index) * 8))
                }
            }
            if (tag(0, "GIF")) return true
            val png = bytes.size >= 8 && bytes[0] == 0x89.toByte() && tag(1, "PNG")
            val webp = tag(0, "RIFF") && tag(8, "WEBP")
            if (!png && !webp) return false
            var offset = if (png) 8 else 12
            while (offset.toLong() + 8 <= bytes.size.toLong()) {
                val length = unsignedInt(if (png) offset else offset + 4, webp)
                if (tag(if (png) offset + 4 else offset, if (png) "acTL" else "ANIM")) return true
                val next = offset.toLong() + length + (if (png) 12 else 8) + (if (webp) length % 2 else 0)
                if (length < 0 || next > bytes.size || next <= offset) break
                offset = next.toInt()
            }
            return false
        }

        private fun atomicWrite(file: File, bytes: ByteArray) {
            val atomic = AtomicFile(file)
            val output = atomic.startWrite()
            try { output.write(bytes); atomic.finishWrite(output) }
            catch (error: Throwable) { atomic.failWrite(output); throw error }
        }
    }
}
