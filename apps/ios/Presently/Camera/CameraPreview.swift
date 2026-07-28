import AVFoundation
import AVKit
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isCaptureEnabled: Bool
    let onCapture: () -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.installCaptureInteraction(onCapture: onCapture)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.captureAction = onCapture
        uiView.setCaptureInteractionEnabled(isCaptureEnabled)
    }
}

final class PreviewView: UIView {
    var captureAction: (() -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("PreviewView must use AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    func installCaptureInteraction(onCapture: @escaping () -> Void) {
        captureAction = onCapture
        guard #available(iOS 17.2, *) else { return }

        let interaction = AVCaptureEventInteraction { [weak self] event in
            guard event.phase == .ended else { return }
            self?.captureAction?()
        }
        addInteraction(interaction)
    }

    func setCaptureInteractionEnabled(_ isEnabled: Bool) {
        guard #available(iOS 17.2, *) else { return }
        interactions
            .compactMap { $0 as? AVCaptureEventInteraction }
            .forEach { $0.isEnabled = isEnabled }
    }
}
