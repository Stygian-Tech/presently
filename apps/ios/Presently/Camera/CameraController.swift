@preconcurrency import AVFoundation
import Observation

@MainActor
@Observable
final class CameraController: NSObject {
    enum Facing: Equatable, Sendable {
        case back
        case front
    }

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
    var facing: Facing = .back
    var zoomFactor = 1.0
    var minimumZoomFactor = 1.0
    var maximumZoomFactor = 1.0
    var canSwitchCamera = false
    var isSwitchingCamera = false

    var quickZoomFactors: [Double] {
        [0.5, 1, 2, 3].filter {
            $0 >= minimumZoomFactor - 0.01 && $0 <= maximumZoomFactor + 0.01
        }
    }

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
            let capabilities = try await cameraSession.start(facing: facing)
            apply(capabilities)
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

    func switchCamera() async {
        guard state == .ready, !isSwitchingCamera else { return }
        isSwitchingCamera = true
        defer { isSwitchingCamera = false }

        let requestedFacing: Facing = facing == .back ? .front : .back
        do {
            let capabilities = try await cameraSession.switchCamera(to: requestedFacing)
            facing = requestedFacing
            apply(capabilities)
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func setZoomFactor(_ requestedZoomFactor: Double) {
        let zoomFactor = min(max(requestedZoomFactor, minimumZoomFactor), maximumZoomFactor)
        self.zoomFactor = zoomFactor
        cameraSession.setZoomFactor(zoomFactor)
    }

    func retake() {
        capturedPhotoData = nil
    }

    private func apply(_ capabilities: CameraCapabilities) {
        zoomFactor = capabilities.zoomFactor
        minimumZoomFactor = capabilities.minimumZoomFactor
        maximumZoomFactor = capabilities.maximumZoomFactor
        canSwitchCamera = capabilities.canSwitchCamera
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
    private var cameraInput: AVCaptureDeviceInput?
    private var zoomDisplayScale = 1.0
    private var isConfigured = false

    func start(facing: CameraController.Facing) async throws -> CameraCapabilities {
        try await sessionQueue.perform { [self] in
            let capabilities = try configure(facing: facing)
            if !session.isRunning {
                session.startRunning()
            }
            return capabilities
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
            settings.photoQualityPrioritization = .quality
            photoOutput.capturePhoto(with: settings, delegate: delegate.value)
        }
    }

    func switchCamera(to facing: CameraController.Facing) async throws -> CameraCapabilities {
        try await sessionQueue.perform { [self] in
            try configure(facing: facing)
        }
    }

    func setZoomFactor(_ zoomFactor: Double) {
        sessionQueue.perform { [self] in
            guard let camera else { return }
            let deviceZoomFactor = CGFloat(zoomFactor / zoomDisplayScale)
            let clampedZoomFactor = min(
                max(deviceZoomFactor, camera.minAvailableVideoZoomFactor),
                camera.maxAvailableVideoZoomFactor
            )
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = clampedZoomFactor
                camera.unlockForConfiguration()
            } catch {
                return
            }
        }
    }

    private func configure(
        facing: CameraController.Facing
    ) throws -> CameraCapabilities {
        guard let camera = Self.camera(for: facing) else {
            throw facing == .back ? CameraError.noBackCamera : CameraError.noFrontCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        if let cameraInput {
            session.removeInput(cameraInput)
        }

        guard session.canAddInput(input) else {
            if let cameraInput, session.canAddInput(cameraInput) {
                session.addInput(cameraInput)
            }
            throw CameraError.configurationFailed
        }

        session.addInput(input)

        if !isConfigured {
            guard session.canAddOutput(photoOutput) else {
                session.removeInput(input)
                throw CameraError.configurationFailed
            }
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            isConfigured = true
        }

        zoomDisplayScale = Self.zoomDisplayScale(for: camera)
        let minimumZoomFactor = Double(camera.minAvailableVideoZoomFactor) * zoomDisplayScale
        let maximumZoomFactor = Double(camera.maxAvailableVideoZoomFactor) * zoomDisplayScale
        let preferredZoomFactor = min(max(1, minimumZoomFactor), maximumZoomFactor)

        try camera.lockForConfiguration()
        camera.videoZoomFactor = CGFloat(preferredZoomFactor / zoomDisplayScale)
        camera.unlockForConfiguration()

        self.camera = camera
        cameraInput = input

        return CameraCapabilities(
            zoomFactor: preferredZoomFactor,
            minimumZoomFactor: minimumZoomFactor,
            maximumZoomFactor: maximumZoomFactor,
            canSwitchCamera: Self.camera(for: facing == .back ? .front : .back) != nil
        )
    }

    private static func camera(
        for facing: CameraController.Facing
    ) -> AVCaptureDevice? {
        let position: AVCaptureDevice.Position = facing == .back ? .back : .front
        let deviceTypes: [AVCaptureDevice.DeviceType] = facing == .back
            ? [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
            ]
            : [
                .builtInTrueDepthCamera,
                .builtInWideAngleCamera,
            ]

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        ).devices.first
    }

    private static func zoomDisplayScale(for camera: AVCaptureDevice) -> Double {
        guard camera.deviceType == .builtInTripleCamera ||
                camera.deviceType == .builtInDualWideCamera,
              let firstSwitchFactor = camera.virtualDeviceSwitchOverVideoZoomFactors.first
        else {
            return 1
        }

        return 1 / firstSwitchFactor.doubleValue
    }
}

private struct CameraCapabilities: Sendable {
    let zoomFactor: Double
    let minimumZoomFactor: Double
    let maximumZoomFactor: Double
    let canSwitchCamera: Bool
}

private final class PhotoCaptureDelegate: @unchecked Sendable {
    let value: AVCapturePhotoCaptureDelegate

    init(_ value: AVCapturePhotoCaptureDelegate) {
        self.value = value
    }
}

private enum CameraError: LocalizedError {
    case noBackCamera
    case noFrontCamera
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .noBackCamera:
            "No back camera is available on this device."
        case .noFrontCamera:
            "No front camera is available on this device."
        case .configurationFailed:
            "Presently could not configure the camera."
        }
    }
}
