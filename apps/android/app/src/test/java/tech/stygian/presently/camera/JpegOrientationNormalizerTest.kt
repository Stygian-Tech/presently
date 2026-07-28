package tech.stygian.presently.camera

import androidx.exifinterface.media.ExifInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JpegOrientationNormalizerTest {
    @Test
    fun rotatesCounterclockwiseExifCaptureClockwise() {
        assertEquals(
            JpegOrientationTransform(rotationDegrees = 90f),
            JpegOrientationNormalizer.transformFor(
                ExifInterface.ORIENTATION_ROTATE_90,
            ),
        )
    }

    @Test
    fun rotatesClockwiseExifCaptureCounterclockwise() {
        assertEquals(
            JpegOrientationTransform(rotationDegrees = -90f),
            JpegOrientationNormalizer.transformFor(
                ExifInterface.ORIENTATION_ROTATE_270,
            ),
        )
    }

    @Test
    fun leavesNormalJpegUnchanged() {
        assertTrue(
            JpegOrientationNormalizer.transformFor(
                ExifInterface.ORIENTATION_NORMAL,
            ).isIdentity,
        )
    }
}
