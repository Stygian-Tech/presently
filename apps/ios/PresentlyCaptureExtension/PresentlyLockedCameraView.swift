import AppIntents
import LockedCameraCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PresentlyLockedCameraRootView: View {
    let session: LockedCameraCaptureSession
    @State private var cameraDevice = UIImagePickerController.CameraDevice.rear

    var body: some View {
        PresentlyLockedCameraView(
            session: session,
            cameraDevice: cameraDevice
        )
        .task {
            guard let context = try? await PresentlyCaptureIntent.appContext else {
                return
            }
            cameraDevice = context.facing == .back ? .rear : .front
        }
    }
}

struct PresentlyLockedCameraView: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession
    let cameraDevice: UIImagePickerController.CameraDevice

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        if UIImagePickerController.isCameraDeviceAvailable(cameraDevice) {
            picker.cameraDevice = cameraDevice
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {
        guard UIImagePickerController.isCameraDeviceAvailable(cameraDevice),
              uiViewController.cameraDevice != cameraDevice else {
            return
        }
        uiViewController.cameraDevice = cameraDevice
    }

    final class Coordinator: NSObject,
        UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {
        private let session: LockedCameraCaptureSession

        init(session: LockedCameraCaptureSession) {
            self.session = session
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [
                UIImagePickerController.InfoKey: Any
            ]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.95)
            else {
                return
            }

            let destination = session.sessionContentURL
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try? data.write(to: destination, options: .atomic)
        }
    }
}
