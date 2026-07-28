package tech.stygian.presently.camera

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

internal data class JpegOrientationTransform(
    val rotationDegrees: Float = 0f,
    val horizontalScale: Float = 1f,
    val verticalScale: Float = 1f,
) {
    val isIdentity: Boolean
        get() = rotationDegrees == 0f &&
            horizontalScale == 1f &&
            verticalScale == 1f
}

internal object JpegOrientationNormalizer {
    fun normalize(jpegData: ByteArray): ByteArray {
        val orientation = ExifInterface(ByteArrayInputStream(jpegData))
            .getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        val transform = transformFor(orientation)
        if (transform.isIdentity) return jpegData

        val source = requireNotNull(
            BitmapFactory.decodeByteArray(jpegData, 0, jpegData.size),
        ) { "Android could not decode the captured photo." }
        val matrix = Matrix().apply {
            setRotate(transform.rotationDegrees)
            postScale(transform.horizontalScale, transform.verticalScale)
        }
        val normalized = Bitmap.createBitmap(
            source,
            0,
            0,
            source.width,
            source.height,
            matrix,
            true,
        )
        if (normalized !== source) source.recycle()

        return try {
            ByteArrayOutputStream().use { output ->
                check(normalized.compress(Bitmap.CompressFormat.JPEG, 95, output)) {
                    "Android could not normalize the captured photo."
                }
                output.toByteArray()
            }
        } finally {
            normalized.recycle()
        }
    }

    fun transformFor(orientation: Int): JpegOrientationTransform =
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL ->
                JpegOrientationTransform(horizontalScale = -1f)
            ExifInterface.ORIENTATION_ROTATE_180 ->
                JpegOrientationTransform(rotationDegrees = 180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL ->
                JpegOrientationTransform(verticalScale = -1f)
            ExifInterface.ORIENTATION_TRANSPOSE ->
                JpegOrientationTransform(
                    rotationDegrees = 90f,
                    horizontalScale = -1f,
                )
            ExifInterface.ORIENTATION_ROTATE_90 ->
                JpegOrientationTransform(rotationDegrees = 90f)
            ExifInterface.ORIENTATION_TRANSVERSE ->
                JpegOrientationTransform(
                    rotationDegrees = -90f,
                    horizontalScale = -1f,
                )
            ExifInterface.ORIENTATION_ROTATE_270 ->
                JpegOrientationTransform(rotationDegrees = -90f)
            else -> JpegOrientationTransform()
        }
}
