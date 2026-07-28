import ExtensionKit
import LockedCameraCapture
import SwiftUI

@main
struct PresentlyCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            PresentlyLockedCameraView(session: session)
        }
    }
}
