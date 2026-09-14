package tech.stygian.presently.editor

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.cos
import kotlin.math.sin

/** Coordinates and text sizes are fractions of the orientation-normalized image width/height. */
internal data class StoryLayer(
    val id: String = UUID.randomUUID().toString(),
    val text: String = "",
    val asset: String? = null,
    val x: Float = 0.5f,
    val y: Float = 0.5f,
    val scale: Float = 1f,
    val rotation: Float = 0f,
    val color: Int = -1,
    val style: String = "bold",
    val alignment: String = "center",
    val background: Boolean = false,
) {
    fun transformed(dx: Float, dy: Float, zoom: Float, degrees: Float): StoryLayer = copy(
        x = (x + dx).coerceIn(0f, 1f),
        y = (y + dy).coerceIn(0f, 1f),
        scale = (scale * zoom).coerceIn(0.2f, 5f),
        rotation = ((rotation + degrees) % 360f + 360f) % 360f,
    )
}

internal data class StoryComposition(val layers: List<StoryLayer> = emptyList()) {
    fun encode(): String = JSONObject().apply {
        put("version", 1)
        put("layers", JSONArray().apply {
            layers.forEach { layer -> put(JSONObject().apply {
                put("id", layer.id); put("text", layer.text)
                layer.asset?.let { put("asset", it) }
                put("x", layer.x); put("y", layer.y); put("scale", layer.scale)
                put("rotation", layer.rotation); put("color", layer.color)
                put("style", layer.style); put("alignment", layer.alignment)
                put("background", layer.background)
            }) }
        })
    }.toString()

    companion object {
        const val MaximumLayers = 30
        const val MaximumTextLength = 500

        fun decode(json: String?): StoryComposition {
            if (json == null) return StoryComposition()
            val root = JSONObject(json)
            require(root.getInt("version") == 1) { "This draft needs a newer version of Presently." }
            val items = root.getJSONArray("layers")
            require(items.length() <= MaximumLayers) { "The story has too many layers." }
            return StoryComposition((0 until items.length()).map { index ->
                val item = items.getJSONObject(index)
                fun finite(name: String, default: Double): Float = item.optDouble(name, default)
                    .toFloat().also { require(it.isFinite()) { "Invalid layer position." } }
                val asset = if (item.has("asset")) item.getString("asset") else null
                require(asset == null || asset.matches(Regex("[a-zA-Z0-9-]+\\.png"))) {
                    "Invalid sticker asset."
                }
                StoryLayer(
                    id = item.getString("id"),
                    text = item.optString("text").take(MaximumTextLength), asset = asset,
                    x = finite("x", 0.5).coerceIn(0f, 1f),
                    y = finite("y", 0.5).coerceIn(0f, 1f),
                    scale = finite("scale", 1.0).coerceIn(0.2f, 5f),
                    rotation = finite("rotation", 0.0), color = item.optInt("color", -1),
                    style = item.optString("style", "bold").takeIf { it in listOf("bold", "classic", "mono") } ?: "bold",
                    alignment = item.optString("alignment", "center").takeIf { it in listOf("left", "center", "right") } ?: "center",
                    background = item.optBoolean("background"),
                )
            })
        }
    }
}

internal data class ImageFrame(val left: Float, val top: Float, val width: Float, val height: Float) {
    companion object {
        fun fit(imageWidth: Int, imageHeight: Int, viewWidth: Int, viewHeight: Int): ImageFrame {
            val factor = minOf(viewWidth.toFloat() / imageWidth, viewHeight.toFloat() / imageHeight)
            val width = imageWidth * factor
            val height = imageHeight * factor
            return ImageFrame((viewWidth - width) / 2, (viewHeight - height) / 2, width, height)
        }
    }
}

internal fun layerLocalPoint(layer: StoryLayer, x: Float, y: Float, width: Float, height: Float): Pair<Float, Float> {
    val radians = Math.toRadians(-layer.rotation.toDouble())
    val dx = x - layer.x * width
    val dy = y - layer.y * height
    return Pair(
        (dx * cos(radians) - dy * sin(radians)).toFloat() / layer.scale,
        (dx * sin(radians) + dy * cos(radians)).toFloat() / layer.scale,
    )
}
