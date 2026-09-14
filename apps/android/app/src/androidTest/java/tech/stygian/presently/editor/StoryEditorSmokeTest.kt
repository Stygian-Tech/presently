package tech.stygian.presently.editor

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.SystemClock
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.UiScrollable
import androidx.test.uiautomator.UiSelector
import androidx.test.uiautomator.Until
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.FixMethodOrder
import org.junit.runners.MethodSorters
import org.junit.runner.RunWith
import tech.stygian.presently.MainActivity
import tech.stygian.presently.data.PresentlyDatabase
import java.io.ByteArrayOutputStream
import java.io.File

/** Run edit and restore methods separately, with host force-stop/relaunch between phases.
 * Fixtures create their own draft; existing user drafts and account state are preserved.
 * This smoke test deliberately never invokes Post or opens account authorization.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class StoryEditorSmokeTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val store = StoryEditorStore(context, PresentlyDatabase.get(context).presentlyDao())
    private val fixturePreferences = context.getSharedPreferences("editor-smoke-test-fixture", Context.MODE_PRIVATE)

    @Test fun editStoryAndExerciseUndoDelete() {
        val source = Bitmap.createBitmap(800, 1200, Bitmap.Config.ARGB_8888)
        Canvas(source).apply {
            drawColor(0xFF32748C.toInt())
            drawCircle(400f, 700f, 300f, Paint().apply { color = 0xFFD9B277.toInt() })
        }
        val jpeg = ByteArrayOutputStream().use { source.compress(Bitmap.CompressFormat.JPEG, 95, it); it.toByteArray() }
        source.recycle()
        val draft = runBlocking {
            store.restore()?.takeIf { it.id == fixturePreferences.getString("draftId", null) }?.let { store.discard(it) }
            store.create(jpeg)
        }
        assertTrue(fixturePreferences.edit().putString("draftId", draft.id).commit())
        launchEditor()
        var fixtureUri: Uri? = null
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        var previousClip: ClipData? = null
        instrumentation.runOnMainSync { previousClip = clipboard.primaryClip }
        try {
            button("Text").click()
            val input = requireNotNull(device.wait(Until.findObject(By.clazz("android.widget.EditText")), 5000))
            input.text = "Native editor smoke"
            button("Done").click()
            awaitComposition { it.layers.size == 1 && it.layers[0].text == "Native editor smoke" }

            button("Emoji").click()
            button("Done").click()
            awaitComposition { it.layers.size == 2 && it.layers[1].text == "✨" }

            val sticker = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
            Canvas(sticker).drawCircle(64f, 64f, 56f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.MAGENTA })
            fixtureUri = requireNotNull(context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "Presently editor smoke sticker.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            }))
            context.contentResolver.openOutputStream(fixtureUri)?.use { sticker.compress(Bitmap.CompressFormat.PNG, 100, it) }
            sticker.recycle()
            instrumentation.runOnMainSync {
                clipboard.setPrimaryClip(ClipData.newUri(context.contentResolver, "Smoke sticker", fixtureUri))
            }
            button("Paste").click()
            awaitComposition { it.layers.size == 3 && it.layers.last().asset != null }
            button("Undo").click()
            awaitComposition { it.layers.size == 2 }
            button("Paste").click()
            awaitComposition { it.layers.size == 3 && it.layers.last().asset != null }

            button("Layers").click()
            button("2. ✨").click()
            button("Delete").click()
            awaitComposition { it.layers.size == 2 && it.layers.none { layer -> layer.text == "✨" } }
            button("Undo").click()
            awaitComposition { it.layers.size == 3 && it.layers.any { layer -> layer.text == "✨" } }

            button("Layers").click()
            button("3. Image sticker").click()
            button("Rotate").click()
            button("Right").click()
            button("Down").click()
            button("Larger").click()
            val edited = awaitComposition {
                it.layers.last().rotation == 15f && it.layers.last().x > 0.5f && it.layers.last().y > 0.5f && it.layers.last().scale > 1f
            }
            assertTrue(fixturePreferences.edit().putString("composition", edited.encode()).commit())
            screenshot("edited")
            assertTrue(button("Post photo", description = true).isEnabled)
        } catch (error: Throwable) {
            screenshot("failure")
            throw error
        } finally {
            instrumentation.runOnMainSync {
                previousClip?.let { clipboard.setPrimaryClip(it) } ?: run {
                    if (android.os.Build.VERSION.SDK_INT >= 28) clipboard.clearPrimaryClip()
                    else clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                }
            }
            fixtureUri?.let { context.contentResolver.delete(it, null, null) }
        }
    }

    @Test fun verifyRestoredStory() {
        val expected = requireNotNull(fixturePreferences.getString("composition", null)) { "Run editStoryAndExerciseUndoDelete first." }
        launchEditor()
        try {
            val actual = awaitComposition { it.encode() == expected }
            assertEquals(3, actual.layers.size)
            button("Layers").click()
            assertNotNull(button("1. Native editor smoke"))
            assertNotNull(button("2. ✨"))
            assertNotNull(button("3. Image sticker"))
            button("Close").click()
            screenshot("restored")
            assertTrue(button("Post photo", description = true).isEnabled)
        } catch (error: Throwable) { screenshot("restore-failure"); throw error }
    }

    private fun launchEditor() {
        device.executeShellCommand("pm grant tech.stygian.presently android.permission.CAMERA")
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
        assertTrue(device.wait(Until.hasObject(By.text("Text")), 10_000))
    }

    private fun button(text: String, description: Boolean = false): UiObject2 {
        val selector = if (description) By.desc(text) else By.text(text)
        refreshAccessibility()
        device.wait(Until.findObject(selector), 1000)?.let { return it }
        if (!description) {
            val scrollables = device.findObjects(By.scrollable(true)).size
            for (index in 0 until scrollables) {
                runCatching {
                    UiScrollable(UiSelector().scrollable(true).instance(index)).setAsHorizontalList().setMaxSearchSwipes(4)
                        .scrollIntoView(UiSelector().text(text))
                }
                refreshAccessibility()
                device.wait(Until.findObject(selector), 1000)?.let { return it }
            }
        }
        return requireNotNull(device.wait(Until.findObject(selector), 3000)) { "Missing control: $text" }
    }

    private fun refreshAccessibility() {
        runCatching { device.waitForIdle(1000) }
        // Compose's horizontal rows can leave a stale UiAutomator node cache after a scroll.
        if (android.os.Build.VERSION.SDK_INT >= 34) instrumentation.uiAutomation.clearCache()
    }

    private fun awaitComposition(predicate: (StoryComposition) -> Boolean): StoryComposition {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        var last = StoryComposition()
        do {
            val draft = runBlocking { store.restore() }
            if (draft != null && draft.id == fixturePreferences.getString("draftId", null)) {
                last = StoryComposition.decode(draft.compositionJson)
                if (predicate(last)) return last
            }
            SystemClock.sleep(100)
        } while (SystemClock.elapsedRealtime() < deadline)
        error("Expected editor state was not persisted: ${last.encode()}")
    }

    private fun screenshot(name: String) {
        val directory = File(context.getExternalFilesDir(null), "editor-smoke").apply { mkdirs() }
        device.takeScreenshot(File(directory, "$name.png"))
        device.dumpWindowHierarchy(File(directory, "$name.xml"))
    }
}
