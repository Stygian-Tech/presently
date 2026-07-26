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

    private let cameraSession = CameraSession()

    var session: AVCaptureSession {
        cameraSession.session
    }

    var state: State = .idle
    var capturedPhotoData: Data?
    var isCapturing = false

    func start() async {
        guard state != .ready else { return }

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
            try await cameraSession.start()
            state = .ready
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func stop() {
        state = .idle
        cameraSession.stop()
    }

    func capture() {
        guard state == .ready, !isCapturing else { return }
        isCapturing = true

        cameraSession.capture(delegate: self)
    }

    func retake() {
        capturedPhotoData = nil
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

final class CameraSessionQueue: @unchecked Sendable {
    private let queue: DispatchQueue

    init(label: String) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func perform(_ operation: @escaping @Sendable () -> Void) {
        queue.async(execute: operation)
    }
}

private final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = CameraSessionQueue(label: "tech.stygian.presently.camera-session")
    private var camera: AVCaptureDevice?
    private var isConfigured = false

    func start() async throws {
        try await sessionQueue.perform { [self] in
            try configureIfNeeded()
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.perform { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func capture(delegate: AVCapturePhotoCaptureDelegate) {
        let delegate = PhotoCaptureDelegate(delegate)
        sessionQueue.perform { [self, delegate] in
            let settings = AVCapturePhotoSettings()
            if camera?.hasFlash == true {
                settings.flashMode = .auto
            }
            photoOutput.capturePhoto(with: settings, delegate: delegate.value)
        }
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
        self.camera = camera
        isConfigured = true
    }
}

private final class PhotoCaptureDelegate: @unchecked Sendable {
    let value: AVCapturePhotoCaptureDelegate

    init(_ value: AVCapturePhotoCaptureDelegate) {
        self.value = value
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
