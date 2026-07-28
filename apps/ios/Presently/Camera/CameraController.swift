@preconcurrency import AVFoundation
import Observation

enum SelfieFramingMode: String, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}

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

    override init() {
        super.init()
        cameraSession.onZoomChanged = { [weak self] zoomFactor in
            Task { @MainActor in
                self?.zoomFactor = zoomFactor
            }
        }
        cameraSession.onCameraChanged = { [weak self] facing, capabilities in
            Task { @MainActor in
                guard let self else { return }
                self.facing = facing
                self.apply(capabilities)
                await self.updateCaptureContext()
            }
        }
        cameraSession.onError = { [weak self] message in
            Task { @MainActor in
                self?.state = .unavailable(message)
            }
        }
    }

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
    var selfieFramingMode = SelfieFramingMode.portrait
    var supportsSmartSelfieFraming = false

    var quickZoomFactors: [Double] {
        [0.5, 1, 2, 3].filter {
            $0 >= minimumZoomFactor - 0.01 && $0 <= maximumZoomFactor + 0.01
        }
    }

    func start() async {
        guard state != .ready else { return }

        state = .requestingPermission
        if #available(iOS 18.0, *),
           let context = try? await PresentlyCaptureIntent.appContext {
            facing = Facing(context.facing)
        }
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
            await updateCaptureContext()
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func setZoomFactor(_ requestedZoomFactor: Double) {
        guard !supportsSmartSelfieFraming else { return }
        let zoomFactor = min(max(requestedZoomFactor, minimumZoomFactor), maximumZoomFactor)
        self.zoomFactor = zoomFactor
        cameraSession.setZoomFactor(zoomFactor)
    }

    func setSelfieFramingMode(_ mode: SelfieFramingMode) {
        guard facing == .front, supportsSmartSelfieFraming else { return }
        selfieFramingMode = mode
        cameraSession.setSelfieFramingMode(mode)
    }

    func retake() {
        capturedPhotoData = nil
    }

    private func apply(_ capabilities: CameraCapabilities) {
        zoomFactor = capabilities.zoomFactor
        minimumZoomFactor = capabilities.minimumZoomFactor
        maximumZoomFactor = capabilities.maximumZoomFactor
        canSwitchCamera = capabilities.canSwitchCamera
        supportsSmartSelfieFraming = capabilities.supportsSmartSelfieFraming
        if supportsSmartSelfieFraming {
            selfieFramingMode = .portrait
        }
    }

    private func updateCaptureContext() async {
        guard #available(iOS 18.0, *) else { return }
        try? await PresentlyCaptureIntent.updateAppContext(
            PresentlyCaptureContext(facing: facing.captureFacing)
        )
    }
}

private extension CameraController.Facing {
    init(_ facing: PresentlyCaptureFacing) {
        self = facing == .back ? .back : .front
    }

    var captureFacing: PresentlyCaptureFacing {
        self == .back ? .back : .front
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
    let queue: DispatchQueue

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

private final class CameraSession: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = CameraSessionQueue(label: "tech.stygian.presently.camera-session")
    private var camera: AVCaptureDevice?
    private var cameraInput: AVCaptureDeviceInput?
    private var zoomDisplayScale = 1.0
    private var isConfigured = false
    private var smartFramingCoordinator: AnyObject?
    var onZoomChanged: (@Sendable (Double) -> Void)?
    var onCameraChanged: (
        @Sendable (CameraController.Facing, CameraCapabilities) -> Void
    )?
    var onError: (@Sendable (String) -> Void)?

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
            stopSmartFraming()
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

    func setSelfieFramingMode(_ mode: SelfieFramingMode) {
        guard #available(iOS 26.0, *) else { return }
        sessionQueue.perform { [self] in
            (smartFramingCoordinator as? SmartFramingCoordinator)?.setMode(mode)
        }
    }

    private func configure(
        facing: CameraController.Facing
    ) throws -> CameraCapabilities {
        guard let camera = Self.camera(for: facing) else {
            throw facing == .back ? CameraError.noBackCamera : CameraError.noFrontCamera
        }

        stopSmartFraming()
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

        var supportsSmartSelfieFraming = false
        try camera.lockForConfiguration()
        if facing == .front, #available(iOS 26.0, *),
           let smartFormat = Self.preferredSmartFramingFormat(for: camera) {
            camera.activeFormat = smartFormat
        }
        zoomDisplayScale = Self.zoomDisplayScale(for: camera)
        let minimumZoomFactor = Double(camera.minAvailableVideoZoomFactor) * zoomDisplayScale
        let maximumZoomFactor = Double(camera.maxAvailableVideoZoomFactor) * zoomDisplayScale
        let preferredZoomFactor = min(max(1, minimumZoomFactor), maximumZoomFactor)
        camera.videoZoomFactor = CGFloat(preferredZoomFactor / zoomDisplayScale)
        camera.unlockForConfiguration()

        self.camera = camera
        cameraInput = input
        configureCameraControls(for: camera, facing: facing)

        if facing == .front, #available(iOS 26.0, *),
           camera.activeFormat.isSmartFramingSupported,
           let coordinator = try? SmartFramingCoordinator(
                camera: camera,
                initialMode: .portrait
           ) {
            smartFramingCoordinator = coordinator
            supportsSmartSelfieFraming = true
        }

        return CameraCapabilities(
            zoomFactor: preferredZoomFactor,
            minimumZoomFactor: minimumZoomFactor,
            maximumZoomFactor: maximumZoomFactor,
            canSwitchCamera: Self.camera(for: facing == .back ? .front : .back) != nil,
            supportsSmartSelfieFraming: supportsSmartSelfieFraming
        )
    }

    private func configureCameraControls(
        for camera: AVCaptureDevice,
        facing: CameraController.Facing
    ) {
        guard #available(iOS 18.0, *), session.supportsControls else { return }

        session.setControlsDelegate(self, queue: sessionQueue.queue)
        for control in session.controls {
            session.removeControl(control)
        }

        let zoomControl = AVCaptureSystemZoomSlider(device: camera) {
            [weak self, weak camera] zoomFactor in
            guard let self, let camera else { return }
            let displayZoomFactor = Double(
                zoomFactor * camera.displayVideoZoomFactorMultiplier
            )
            onZoomChanged?(displayZoomFactor)
        }
        if session.canAddControl(zoomControl) {
            session.addControl(zoomControl)
        }

        guard Self.camera(for: .back) != nil,
              Self.camera(for: .front) != nil
        else {
            return
        }

        let cameraPicker = AVCaptureIndexPicker(
            "Camera",
            symbolName: "arrow.triangle.2.circlepath.camera",
            localizedIndexTitles: ["Back", "Front"]
        )
        cameraPicker.setActionQueue(sessionQueue.queue) {
            [weak self] selectedIndex in
            guard let self else { return }
            let selectedFacing: CameraController.Facing =
                selectedIndex == 0 ? .back : .front
            guard selectedFacing != facing else { return }

            do {
                let capabilities = try configure(facing: selectedFacing)
                onCameraChanged?(selectedFacing, capabilities)
            } catch {
                onError?(error.localizedDescription)
            }
        }
        cameraPicker.selectedIndex = facing == .back ? 0 : 1
        if session.canAddControl(cameraPicker) {
            session.addControl(cameraPicker)
        }
    }

    private func stopSmartFraming() {
        guard #available(iOS 26.0, *) else {
            smartFramingCoordinator = nil
            return
        }
        (smartFramingCoordinator as? SmartFramingCoordinator)?.stop()
        smartFramingCoordinator = nil
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
                .builtInUltraWideCamera,
                .builtInTrueDepthCamera,
                .builtInWideAngleCamera,
            ]

        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        ).devices

        if facing == .front, #available(iOS 26.0, *),
           let smartFramingCamera = devices.first(where: {
               preferredSmartFramingFormat(for: $0) != nil
           }) {
            return smartFramingCamera
        }

        return devices.first
    }

    @available(iOS 26.0, *)
    private static func preferredSmartFramingFormat(
        for camera: AVCaptureDevice
    ) -> AVCaptureDevice.Format? {
        camera.formats
            .filter {
                $0.isSmartFramingSupported &&
                    $0.supportedDynamicAspectRatios.contains(.ratio3x4) &&
                    $0.supportedDynamicAspectRatios.contains(.ratio4x3)
            }
            .max {
                let left = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let right = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return Int(left.width) * Int(left.height) < Int(right.width) * Int(right.height)
            }
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

@available(iOS 18.0, *)
extension CameraSession: AVCaptureSessionControlsDelegate {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {}

    func sessionControlsWillEnterFullscreenAppearance(
        _ session: AVCaptureSession
    ) {}

    func sessionControlsWillExitFullscreenAppearance(
        _ session: AVCaptureSession
    ) {}

    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}

private struct CameraCapabilities: Sendable {
    let zoomFactor: Double
    let minimumZoomFactor: Double
    let maximumZoomFactor: Double
    let canSwitchCamera: Bool
    let supportsSmartSelfieFraming: Bool
}

@available(iOS 26.0, *)
private final class SmartFramingCoordinator {
    private let camera: AVCaptureDevice
    private let monitor: AVCaptureSmartFramingMonitor
    private var observation: NSKeyValueObservation?

    init(
        camera: AVCaptureDevice,
        initialMode: SelfieFramingMode
    ) throws {
        guard let monitor = camera.smartFramingMonitor else {
            throw CameraError.configurationFailed
        }

        self.camera = camera
        self.monitor = monitor
        setMode(initialMode)
        observation = monitor.observe(\.recommendedFraming, options: [.new]) {
            [weak self] monitor, _ in
            guard let framing = monitor.recommendedFraming else { return }
            self?.apply(framing)
        }
        try monitor.startMonitoring()
    }

    func setMode(_ mode: SelfieFramingMode) {
        let aspectRatio = aspectRatio(for: mode)
        monitor.enabledFramings = monitor.supportedFramings.filter {
            $0.aspectRatio == aspectRatio
        }
        apply(aspectRatio: aspectRatio, zoomFactor: 1)
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        monitor.stopMonitoring()
    }

    private func apply(_ framing: AVCaptureFraming) {
        apply(
            aspectRatio: framing.aspectRatio,
            zoomFactor: CGFloat(framing.zoomFactor)
        )
    }

    private func apply(
        aspectRatio: AVCaptureDevice.AspectRatio,
        zoomFactor: CGFloat
    ) {
        guard camera.activeFormat.supportedDynamicAspectRatios.contains(aspectRatio) else {
            return
        }

        do {
            try camera.lockForConfiguration()
            camera.setDynamicAspectRatio(aspectRatio)
            camera.videoZoomFactor = min(
                max(zoomFactor, camera.minAvailableVideoZoomFactor),
                camera.maxAvailableVideoZoomFactor
            )
            camera.unlockForConfiguration()
        } catch {
            return
        }
    }

    private func aspectRatio(
        for mode: SelfieFramingMode
    ) -> AVCaptureDevice.AspectRatio {
        switch mode {
        case .portrait:
            .ratio3x4
        case .landscape:
            .ratio4x3
        }
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
