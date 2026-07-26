@preconcurrency import AVFoundation
import Observation

@MainActor
@Observable
final class CameraController: NSObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case ready
        case denied
        case unavailable(String)
    }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false

    var state: State = .idle
    var capturedPhotoData: Data?
    var isCapturing = false

    func start() async {
        guard !session.isRunning else { return }

        state = .requestingPermission
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            authorized = false
        }

        guard authorized else {
            state = .denied
            return
        }

        do {
            try configureIfNeeded()
            session.startRunning()
            state = .ready
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func capture() {
        guard state == .ready, !isCapturing else { return }
        isCapturing = true

        let settings = AVCapturePhotoSettings()
        if let device = AVCaptureDevice.default(for: .video), device.hasFlash {
            settings.flashMode = .auto
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func retake() {
        capturedPhotoData = nil
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else { return }
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.noBackCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        isConfigured = true
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        let message = error?.localizedDescription

        Task { @MainActor [weak self] in
            self?.isCapturing = false
            if let data {
                self?.capturedPhotoData = data
            } else {
                self?.state = .unavailable(message ?? "The camera did not return an image.")
            }
        }
    }
}

private enum CameraError: LocalizedError {
    case noBackCamera
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .noBackCamera:
            "No back camera is available on this device."
        case .configurationFailed:
            "Presently could not configure the camera."
        }
    }
}
