package tech.stygian.presently.editor

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot

internal class StoryCanvasView(context: Context) : View(context) {
    var source: Bitmap? = null
    var assets: Map<String, Bitmap> = emptyMap()
    var composition = StoryComposition()
    var selectedId: String? = null
    var editable = true
    var onChange: (StoryComposition) -> Unit = {}
    var onSelect: (String?) -> Unit = {}
    var onTransforming: (Boolean) -> Unit = {}
    var onEdit: (StoryLayer) -> Unit = {}
    var transforming = false
        private set
    private var previousX = 0f
    private var previousY = 0f
    private var previousSpan = 0f
    private var previousAngle = 0f
    private var pointerCount = 0
    private var startComposition = composition
    private val photoPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val photoBounds = RectF()
    private val guidePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.YELLOW; strokeWidth = 2f; style = Paint.Style.STROKE }
    private val detector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(event: MotionEvent) = true
        override fun onDoubleTap(event: MotionEvent): Boolean {
            if (editable) hit(event.x, event.y)?.takeIf { it.asset == null }?.let(onEdit)
            return true
        }
    })

    init { contentDescription = "Story editor. Select a layer, then drag, pinch to resize, or rotate with two fingers." }

    private fun frame(): ImageFrame? = source?.let { ImageFrame.fit(it.width, it.height, width, height) }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val bitmap = source ?: return
        val f = frame() ?: return
        canvas.save()
        canvas.translate(f.left, f.top)
        canvas.scale(f.width / bitmap.width, f.height / bitmap.height)
        val imageWidth = bitmap.width.toFloat()
        val imageHeight = bitmap.height.toFloat()
        canvas.clipRect(0f, 0f, imageWidth, imageHeight)
        photoBounds.set(0f, 0f, imageWidth, imageHeight)
        canvas.drawBitmap(bitmap, null, photoBounds, photoPaint)
        StoryRenderer.drawLayers(canvas, composition, imageWidth, imageHeight, assets)
        composition.layers.find { it.id == selectedId }?.takeIf { editable }?.let { layer ->
            if (transforming) {
                if (abs(layer.x - 0.5f) < 0.02f) canvas.drawLine(imageWidth / 2, 0f, imageWidth / 2, imageHeight, guidePaint)
                if (abs(layer.y - 0.5f) < 0.02f) canvas.drawLine(0f, imageHeight / 2, imageWidth, imageHeight / 2, guidePaint)
            }
            canvas.save()
            canvas.translate(layer.x * imageWidth, layer.y * imageHeight)
            canvas.rotate(layer.rotation)
            canvas.scale(layer.scale, layer.scale)
            canvas.drawRect(StoryRenderer.bounds(layer, imageWidth, assets), guidePaint)
            canvas.restore()
        }
        canvas.restore()
    }

    private fun hit(x: Float, y: Float): StoryLayer? {
        val f = frame() ?: return null
        if (x < f.left || x > f.left + f.width || y < f.top || y > f.top + f.height) return null
        return composition.layers.asReversed().firstOrNull { layer ->
            val bitmap = source ?: return@firstOrNull false
            val point = layerLocalPoint(layer, (x - f.left) * bitmap.width / f.width, (y - f.top) * bitmap.height / f.height, bitmap.width.toFloat(), bitmap.height.toFloat())
            StoryRenderer.bounds(layer, bitmap.width.toFloat(), assets).contains(point.first, point.second)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!editable) return false
        detector.onTouchEvent(event)
        val f = frame() ?: return false
        val count = event.pointerCount
        val x = if (count > 1) (event.getX(0) + event.getX(1)) / 2 else event.x
        val y = if (count > 1) (event.getY(0) + event.getY(1)) / 2 else event.y
        val span = if (count > 1) hypot(event.getX(1) - event.getX(0), event.getY(1) - event.getY(0)) else 0f
        val angle = if (count > 1) Math.toDegrees(atan2((event.getY(1) - event.getY(0)).toDouble(), (event.getX(1) - event.getX(0)).toDouble())).toFloat() else 0f
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                transforming = true
                onTransforming(true)
                startComposition = composition
                selectedId = hit(event.x, event.y)?.id
                onSelect(selectedId)
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> if (pointerCount == count && selectedId != null) {
                composition = composition.copy(layers = composition.layers.map { layer ->
                    if (layer.id != selectedId) layer else layer.transformed(
                        (x - previousX) / f.width, (y - previousY) / f.height,
                        if (count > 1 && previousSpan > 0f) span / previousSpan else 1f,
                        if (count > 1) angle - previousAngle else 0f,
                    )
                })
            }
            MotionEvent.ACTION_UP -> {
                composition = composition.copy(layers = composition.layers.map { layer ->
                    if (layer.id != selectedId) layer else layer.copy(
                        x = if (abs(layer.x - 0.5f) < 0.02f) 0.5f else layer.x,
                        y = if (abs(layer.y - 0.5f) < 0.02f) 0.5f else layer.y,
                    )
                })
                transforming = false
                if (composition != startComposition) onChange(composition)
                onTransforming(false)
                performClick()
                parent?.requestDisallowInterceptTouchEvent(false)
            }
            MotionEvent.ACTION_CANCEL -> {
                composition = startComposition
                transforming = false
                onTransforming(false)
                parent?.requestDisallowInterceptTouchEvent(false)
            }
        }
        previousX = x; previousY = y; previousSpan = span; previousAngle = angle
        pointerCount = if (event.actionMasked == MotionEvent.ACTION_POINTER_UP) count - 1 else count
        // Rebase after fingers enter/leave; next move establishes its centroid without a jump.
        if (event.actionMasked == MotionEvent.ACTION_POINTER_UP) pointerCount = -1
        invalidate()
        return true
    }

    override fun performClick(): Boolean { super.performClick(); return true }
}
