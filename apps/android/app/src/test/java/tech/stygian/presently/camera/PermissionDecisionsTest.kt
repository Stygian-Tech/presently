package tech.stygian.presently.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PermissionDecisionsTest {
    @Test
    fun initialAndRationaleStatesRequestCameraPermission() {
        assertEquals(
            CameraPermissionAction.REQUEST_PERMISSION,
            cameraPermissionAction(
                hasPermission = false,
                permissionRequestCompleted = false,
                shouldShowRationale = false,
            ),
        )
        assertEquals(
            CameraPermissionAction.REQUEST_PERMISSION,
            cameraPermissionAction(
                hasPermission = false,
                permissionRequestCompleted = true,
                shouldShowRationale = true,
            ),
        )
    }

    @Test
    fun permanentCameraDenialOpensAppSettings() {
        assertEquals(
            CameraPermissionAction.OPEN_APP_SETTINGS,
            cameraPermissionAction(
                hasPermission = false,
                permissionRequestCompleted = true,
                shouldShowRationale = false,
            ),
        )
    }

    @Test
    fun grantedCameraPermissionUsesCamera() {
        assertEquals(
            CameraPermissionAction.GRANTED,
            cameraPermissionAction(
                hasPermission = true,
                permissionRequestCompleted = true,
                shouldShowRationale = false,
            ),
        )
    }

    @Test
    fun legacyPhotoPermissionIsRequestedOnlyWhenNeeded() {
        assertTrue(
            shouldRequestLegacyPhotoLibraryPermission(
                sdkInt = 28,
                shouldSavePhoto = true,
                hasPermission = false,
            ),
        )
        assertFalse(
            shouldRequestLegacyPhotoLibraryPermission(
                sdkInt = 29,
                shouldSavePhoto = true,
                hasPermission = false,
            ),
        )
        assertFalse(
            shouldRequestLegacyPhotoLibraryPermission(
                sdkInt = 28,
                shouldSavePhoto = false,
                hasPermission = false,
            ),
        )
        assertFalse(
            shouldRequestLegacyPhotoLibraryPermission(
                sdkInt = 28,
                shouldSavePhoto = true,
                hasPermission = true,
            ),
        )
    }
}
