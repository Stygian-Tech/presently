import LockedCameraCapture
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PresentlyLockedCameraView: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .rear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

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
