import SwiftUI

/// Live preview and camera controls. The host owns start/stop and capture handling.
@MainActor
public struct CameraViewfinder: View {
    private let camera: CameraController
    private let onCapture: (Double?) -> Void
    @State private var zoomAtGestureStart: Double?
    @State private var viewfinderSize: CGSize = .zero

    /// Called at shutter time with the aspect ratio of the aspect-fill preview.
    /// Freeze this value in the draft before calling `camera.capture()`.
    public init(camera: CameraController, onCapture: @escaping (Double?) -> Void) {
        self.camera = camera
        self.onCapture = onCapture
    }

    public var body: some View {
        ZStack {
            CameraPreview(
                session: camera.session,
                isCaptureEnabled: camera.state == .ready && !camera.isCapturing,
                onCapture: requestCapture
            )
                .onGeometryChange(for: CGSize.self) { geometry in
                    geometry.size
                } action: { size in
                    viewfinderSize = size
                }
                .ignoresSafeArea()
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            guard !camera.supportsSmartSelfieFraming else { return }
                            let startingZoom = zoomAtGestureStart ?? camera.zoomFactor
                            zoomAtGestureStart = startingZoom
                            camera.setZoomFactor(startingZoom * value.magnification)
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = nil
                        }
                )

            VStack {
                Spacer()

                cameraStateMessage

                cameraControls
                    .environment(\.colorScheme, .dark)
            }
        }
    }

    private var cameraControls: some View {
        VStack(spacing: 20) {
            if camera.facing == .front, camera.supportsSmartSelfieFraming {
                Picker("Selfie framing", selection: Binding(
                    get: { camera.selfieFramingMode },
                    set: { camera.setSelfieFramingMode($0) }
                )) {
                    ForEach(SelfieFramingMode.allCases) { mode in
                        Label(
                            mode.title,
                            systemImage: mode == .portrait
                                ? "rectangle.portrait"
                                : "rectangle"
                        )
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .accessibilityHint("Changes the Center Stage photo orientation")
            } else {
                zoomControls
            }

            ZStack {
                Button {
                    requestCapture()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(.white)
                            .frame(width: 66, height: 66)
                    }
                }
                .disabled(camera.state != .ready || camera.isCapturing)
                .accessibilityLabel("Take photo")
                .frame(maxWidth: .infinity)

                Button {
                    Task {
                        await camera.switchCamera()
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                }
                .modifier(PresentlyGlassButtonStyle())
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .disabled(!camera.canSwitchCamera || camera.isSwitchingCamera)
                .accessibilityLabel("Switch camera")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            ForEach(camera.quickZoomFactors, id: \.self) { zoomFactor in
                Button {
                    camera.setZoomFactor(zoomFactor)
                } label: {
                    Text(formatZoom(zoomFactor))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(
                            abs(camera.zoomFactor - zoomFactor) < 0.05 ? .yellow : .white
                        )
                        .frame(minWidth: 44, minHeight: 44)
                        .background(
                            abs(camera.zoomFactor - zoomFactor) < 0.05
                                ? Color.white.opacity(0.16) : Color.clear,
                            in: Capsule()
                        )
                }
                .accessibilityLabel("Zoom \(formatZoom(zoomFactor))")
                .accessibilityAddTraits(abs(camera.zoomFactor - zoomFactor) < 0.05 ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
        .padding(4)
        .modifier(PresentlyControlSurface())
    }

    @ViewBuilder
    private var cameraStateMessage: some View {
        switch camera.state {
        case .idle, .ready:
            EmptyView()
        case .requestingPermission:
            ProgressView("Opening camera…")
                .foregroundStyle(.white)
                .padding()
        case .denied:
            Text("Camera access is required. Enable it in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
        case let .unavailable(message):
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding()
        }
    }

    private func requestCapture() {
        guard camera.state == .ready, !camera.isCapturing else { return }
        onCapture(viewfinderSize.height > 0 ? Double(viewfinderSize.width / viewfinderSize.height) : nil)
    }

    private func formatZoom(_ zoomFactor: Double) -> String {
        if zoomFactor.rounded() == zoomFactor {
            return "\(Int(zoomFactor))×"
        }
        return String(format: "%.1f×", zoomFactor)
    }
}
