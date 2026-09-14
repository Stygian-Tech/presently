package tech.stygian.presently.editor

import org.junit.Assert.*
import org.junit.Test

class StoryCompositionTest {
    @Test fun aspectFitKeepsLetterboxingOutOfCoordinates() {
        assertEquals(ImageFrame(100f, 0f, 300f, 600f), ImageFrame.fit(100, 200, 500, 600))
        assertEquals(ImageFrame(0f, 200f, 400f, 200f), ImageFrame.fit(200, 100, 400, 600))
    }
    @Test fun transformedLayerClampsReachableBoundsAndScale() {
        val layer = StoryLayer(x = 0.8f, y = 0.1f, rotation = 350f).transformed(5f, -2f, 100f, 30f)
        assertEquals(1f, layer.x); assertEquals(0f, layer.y)
        assertEquals(5f, layer.scale); assertEquals(20f, layer.rotation)
        val local = layerLocalPoint(StoryLayer(rotation = 90f, scale = 2f), 50f, 120f, 100f, 200f)
        assertEquals(10f, local.first, 0.001f); assertEquals(0f, local.second, 0.001f)
    }
    @Test fun documentRoundTripPreservesEditableTextStyleAndTransforms() {
        val composition = StoryComposition(listOf(
            StoryLayer(text = "Hello 👩🏽‍🚀\nمرحبا", x = 0.2f, y = 0.7f, scale = 1.7f, rotation = 21f, color = 123, style = "mono", alignment = "right", background = true),
            StoryLayer(asset = "sticker-1.png"),
        ))
        assertEquals(composition, StoryComposition.decode(composition.encode()))
        assertThrows(IllegalArgumentException::class.java) { StoryComposition.decode("{\"version\":2,\"layers\":[]}") }
        assertThrows(IllegalArgumentException::class.java) { StoryComposition.decode(composition.encode().replace("sticker-1.png", "../../secret.png")) }
    }
    @Test fun animationDetectionReadsContainerChunksNotArbitraryMetadata() {
        assertFalse(StoryEditorStore.isAnimatedImage("JPEG EXIF ANIMAL acTL".toByteArray()))
        val pngSignature = byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 13, 10, 26, 10)
        assertTrue(StoryEditorStore.isAnimatedImage(pngSignature + byteArrayOf(0, 0, 0, 8) + "acTL".toByteArray() + ByteArray(12)))
        assertFalse(StoryEditorStore.isAnimatedImage(pngSignature + byteArrayOf(0, 0, 0, 4) + "tEXt".toByteArray() + "ANIM".toByteArray() + ByteArray(4)))
        assertTrue(StoryEditorStore.isAnimatedImage("RIFF".toByteArray() + byteArrayOf(12, 0, 0, 0) + "WEBPANIM".toByteArray() + ByteArray(4)))
    }
}
