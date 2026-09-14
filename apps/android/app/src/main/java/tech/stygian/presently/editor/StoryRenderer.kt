package tech.stygian.presently.editor

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.LruCache
import kotlin.math.ceil
import java.io.ByteArrayOutputStream
import tech.stygian.presently.story.FlashesStoryContract

/** Preview and export share layout, fonts, wrapping, transforms, and clipping. */
internal object StoryRenderer {
    private data class TextLayoutKey(val text: String, val width: Float, val color: Int, val style: String, val alignment: String)
    private val textLayouts = LruCache<TextLayoutKey, StaticLayout>(64)
    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    private fun textLayout(layer: StoryLayer, width: Float): StaticLayout {
        val key = TextLayoutKey(layer.text, width, layer.color, layer.style, layer.alignment)
        textLayouts.get(key)?.let { return it }
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = layer.color
            textSize = width * 0.065f
            typeface = when (layer.style) {
                "mono" -> Typeface.MONOSPACE
                "classic" -> Typeface.SERIF
                else -> Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }
        }
        val naturalWidth = layer.text.split('\n').maxOfOrNull { paint.measureText(it) } ?: 0f
        val layoutWidth = ceil(minOf(width * 0.8f, naturalWidth)).toInt().coerceAtLeast(1)
        return StaticLayout.Builder.obtain(layer.text, 0, layer.text.length, paint, layoutWidth)
            .setAlignment(when (layer.alignment) {
                "left" -> Layout.Alignment.ALIGN_NORMAL
                "right" -> Layout.Alignment.ALIGN_OPPOSITE
                else -> Layout.Alignment.ALIGN_CENTER
            })
            .setIncludePad(true)
            .build().also { textLayouts.put(key, it) }
    }

    fun bounds(layer: StoryLayer, width: Float, assets: Map<String, Bitmap>): RectF {
        val bitmap = layer.asset?.let { assets[it] }
        val w = if (layer.asset == null) textLayout(layer, width).width.toFloat() else width * 0.32f
        val h = if (layer.asset == null) textLayout(layer, width).height.toFloat()
            else bitmap?.let { w * it.height / it.width } ?: w
        return RectF(-w / 2, -h / 2, w / 2, h / 2)
    }

    fun drawLayers(canvas: Canvas, composition: StoryComposition, width: Float, height: Float, assets: Map<String, Bitmap>) {
        composition.layers.forEach { layer ->
            canvas.save()
            canvas.translate(layer.x * width, layer.y * height)
            canvas.rotate(layer.rotation)
            canvas.scale(layer.scale, layer.scale)
            val bounds = bounds(layer, width, assets)
            if (layer.asset != null) {
                assets[layer.asset]?.let { canvas.drawBitmap(it, null, bounds, imagePaint) }
            } else {
                if (layer.background) canvas.drawRoundRect(bounds, width * 0.012f, width * 0.012f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = if (layer.color == Color.BLACK) 0xD9FFFFFF.toInt() else 0xB3000000.toInt() })
                canvas.translate(bounds.left, bounds.top)
                textLayout(layer, width).draw(canvas)
            }
            canvas.restore()
        }
    }

    fun render(source: Bitmap, composition: StoryComposition, assets: Map<String, Bitmap>): ByteArray {
        val factor = minOf(1f, 2048f / maxOf(source.width, source.height))
        val output = Bitmap.createBitmap((source.width * factor).toInt().coerceAtLeast(1), (source.height * factor).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(output)
            canvas.drawColor(Color.BLACK)
            canvas.drawBitmap(source, null, RectF(0f, 0f, output.width.toFloat(), output.height.toFloat()), Paint(Paint.FILTER_BITMAP_FLAG))
            drawLayers(canvas, composition, output.width.toFloat(), output.height.toFloat(), assets)
            for (quality in listOf(95, 85, 75)) {
                val bytes = ByteArrayOutputStream().use { stream ->
                    check(output.compress(Bitmap.CompressFormat.JPEG, quality, stream)) { "The story could not be rendered." }
                    stream.toByteArray()
                }
                if (bytes.size <= FlashesStoryContract.MaximumImageBytes) return bytes
            }
            error("The edited story exceeds the 10 MiB limit.")
        } finally { output.recycle() }
    }
}
