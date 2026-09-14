package tech.stygian.presently.editor

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.net.Uri
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import tech.stygian.presently.data.PresentlyDatabase
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import kotlin.math.abs

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StoryEditorAndroidTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private fun photo(): ByteArray {
        val bitmap = Bitmap.createBitmap(400, 600, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }
        return try { ByteArrayOutputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it); it.toByteArray() } }
        finally { bitmap.recycle() }
    }

    @Test fun originalAndEditsSurviveDatabaseReopenAndFrozenRetryUsesIdenticalBytes() = runBlocking {
        val name = "editor-${UUID.randomUUID()}.db"
        var database = Room.databaseBuilder(context, PresentlyDatabase::class.java, name).build()
        var store = StoryEditorStore(context, database.presentlyDao())
        var draft = store.create(photo())
        val composition = StoryComposition(listOf(StoryLayer(text = "Saved text", x = 0.3f, background = true)))
        draft = store.save(draft, composition)
        database.close()
        database = Room.databaseBuilder(context, PresentlyDatabase::class.java, name).build()
        store = StoryEditorStore(context, database.presentlyDao())
        try {
            val restored = requireNotNull(store.restore())
            assertEquals(draft.id, restored.id)
            assertEquals(composition, StoryComposition.decode(restored.compositionJson))
            assertArrayEquals(photo(), store.source(restored))
            val (frozen, bytes) = store.freeze(restored, composition)
            val retryStore = StoryEditorStore(context, database.presentlyDao())
            val retry = requireNotNull(retryStore.restore())
            val (again, retryBytes) = retryStore.freeze(retry, StoryComposition())
            assertEquals(frozen.recordKey, again.recordKey)
            assertArrayEquals(bytes, retryBytes)
            assertTrue(bytes.size <= 10_485_760)
            try { retryStore.save(again, StoryComposition()); fail("A frozen story must reject edits") } catch (_: IllegalStateException) { }
            store.discard(again)
            assertNull(store.restore())
        } finally { database.close(); context.deleteDatabase(name) }
    }

    @Test fun transparentImportCopiesAssetIntoDraftAndEnforcesPixelBudget() = runBlocking {
        val database = Room.inMemoryDatabaseBuilder(context, PresentlyDatabase::class.java).build()
        val store = StoryEditorStore(context, database.presentlyDao())
        val draft = store.create(photo())
        val file = File(context.cacheDir, "sticker-${UUID.randomUUID()}.png")
        val sticker = Bitmap.createBitmap(1600, 800, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.TRANSPARENT); setPixel(0, 0, Color.RED) }
        file.outputStream().use { sticker.compress(Bitmap.CompressFormat.PNG, 100, it) }; sticker.recycle()
        try {
            val name = store.importSticker(draft, Uri.fromFile(file))
            file.delete()
            val assets = store.loadAssets(draft, StoryComposition(listOf(StoryLayer(asset = name))))
            val image = assets.getValue(name)
            assertTrue(maxOf(image.width, image.height) <= 512)
            assertEquals(0, Color.alpha(image.getPixel(image.width / 2, image.height / 2)))
            assets.values.forEach { it.recycle() }
        } finally { file.delete(); store.discard(draft); database.close() }
    }

    @Test fun previewMatchesExportUsingCanonicalTextLayoutAndLetterboxedImage() {
        val source = BitmapFactory.decodeByteArray(photo(), 0, photo().size)
        val sticker = Bitmap.createBitmap(40, 40, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) }
        val composition = StoryComposition(listOf(
            StoryLayer(text = "A line that wraps predictably across this story 👋", y = 0.2f, color = Color.YELLOW, background = true),
            StoryLayer(asset = "red.png", x = 0.7f, y = 0.65f, rotation = 25f),
        ))
        val assets = mapOf("red.png" to sticker)
        val encoded = StoryRenderer.render(source, composition, assets)
        val exported = BitmapFactory.decodeByteArray(encoded, 0, encoded.size)
        for ((viewWidth, viewHeight) in listOf(400 to 800, 213 to 500)) {
            val view = StoryCanvasView(context).apply {
                this.source = source; this.assets = assets; this.composition = composition; editable = false
                layout(0, 0, viewWidth, viewHeight)
            }
            val preview = Bitmap.createBitmap(viewWidth, viewHeight, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(preview))
            val expected = Bitmap.createBitmap(viewWidth, viewHeight, Bitmap.Config.ARGB_8888)
            val frame = ImageFrame.fit(source.width, source.height, viewWidth, viewHeight)
            Canvas(expected).drawBitmap(exported, null, android.graphics.RectF(frame.left, frame.top, frame.left + frame.width, frame.top + frame.height), android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
            var difference = 0L
            for (y in 0 until viewHeight) for (x in 0 until viewWidth) {
                val a = preview.getPixel(x, y); val b = expected.getPixel(x, y)
                difference += abs(Color.red(a) - Color.red(b)) + abs(Color.green(a) - Color.green(b)) + abs(Color.blue(a) - Color.blue(b))
            }
            val meanError = difference / (viewWidth.toDouble() * viewHeight * 3)
            assertTrue("Preview/export color error at width $viewWidth was $meanError", meanError < 6)
            assertEquals(Color.TRANSPARENT, preview.getPixel(0, 0))
            preview.recycle(); expected.recycle()
        }
        assertTrue(Color.red(exported.getPixel(280, 390)) > 230)
        listOf(source, sticker, exported).forEach { it.recycle() }
    }

    @Test fun shortEmojiHasAContentSizedSelectionTarget() {
        val bounds = StoryRenderer.bounds(StoryLayer(text = "✨"), 400f, emptyMap())
        assertTrue(bounds.width() in 1f..80f)
    }

    @Test fun completedDragCommitsOnceAndBlocksPublishingUntilCommit() {
        val source = BitmapFactory.decodeByteArray(photo(), 0, photo().size)
        val initial = StoryComposition(listOf(StoryLayer(text = "Move me")))
        val changes = mutableListOf<StoryComposition>()
        val events = mutableListOf<String>()
        val view = StoryCanvasView(context).apply {
            this.source = source; composition = initial
            onChange = { changes.add(it); events.add("commit") }
            onTransforming = { events.add(if (it) "begin" else "end") }
            layout(0, 0, 400, 800)
        }
        fun touch(action: Int, x: Float, y: Float, time: Long) {
            val event = android.view.MotionEvent.obtain(0, time, action, x, y, 0)
            view.onTouchEvent(event); event.recycle()
        }
        touch(android.view.MotionEvent.ACTION_DOWN, 200f, 400f, 0)
        touch(android.view.MotionEvent.ACTION_MOVE, 240f, 460f, 100)
        assertTrue(changes.isEmpty())
        assertTrue(view.transforming)
        touch(android.view.MotionEvent.ACTION_UP, 240f, 460f, 200)
        assertEquals(listOf("begin", "commit", "end"), events)
        assertEquals(1, changes.size)
        assertEquals(0.6f, changes.single().layers.single().x, 0.001f)
        assertEquals(0.6f, changes.single().layers.single().y, 0.001f)
        assertFalse(view.transforming)
        source.recycle()
    }

    @Test fun migrationPreservesExistingDraftBytesAndPublicationIdentity() {
        val name = "migration-${UUID.randomUUID()}.db"
        fun helper(version: Int) = FrameworkSQLiteOpenHelperFactory().create(SupportSQLiteOpenHelper.Configuration.builder(context)
            .name(name).callback(object : SupportSQLiteOpenHelper.Callback(version) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL("CREATE TABLE local_story_drafts (id TEXT PRIMARY KEY NOT NULL, imageData BLOB NOT NULL, recordKey TEXT)")
                    db.execSQL("INSERT INTO local_story_drafts VALUES ('original', X'010203', 'existing-key')")
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) { PresentlyDatabase.Migration4To5.migrate(db) }
            }).build())
        helper(4).also { it.writableDatabase; it.close() }
        val migrated = helper(5)
        try {
            migrated.writableDatabase.query("SELECT * FROM local_story_drafts").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertArrayEquals(byteArrayOf(1, 2, 3), cursor.getBlob(cursor.getColumnIndexOrThrow("imageData")))
                assertEquals("existing-key", cursor.getString(cursor.getColumnIndexOrThrow("recordKey")))
                assertTrue(cursor.isNull(cursor.getColumnIndexOrThrow("compositionJson")))
                assertTrue(cursor.isNull(cursor.getColumnIndexOrThrow("originalImagePath")))
                assertTrue(cursor.isNull(cursor.getColumnIndexOrThrow("renderedImagePath")))
            }
        } finally { migrated.close(); context.deleteDatabase(name) }
    }
}
