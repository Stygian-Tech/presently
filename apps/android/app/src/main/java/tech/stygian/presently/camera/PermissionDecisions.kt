package tech.stygian.presently.camera

import android.os.Build

internal enum class CameraPermissionAction {
    GRANTED,
    REQUEST_PERMISSION,
    OPEN_APP_SETTINGS,
}

internal fun cameraPermissionAction(
    hasPermission: Boolean,
    permissionRequestCompleted: Boolean,
    shouldShowRationale: Boolean,
): CameraPermissionAction = when {
    hasPermission -> CameraPermissionAction.GRANTED
    !permissionRequestCompleted || shouldShowRationale ->
        CameraPermissionAction.REQUEST_PERMISSION
    else -> CameraPermissionAction.OPEN_APP_SETTINGS
}

internal fun shouldRequestLegacyPhotoLibraryPermission(
    sdkInt: Int,
    shouldSavePhoto: Boolean,
    hasPermission: Boolean,
): Boolean =
    sdkInt <= Build.VERSION_CODES.P && shouldSavePhoto && !hasPermission
