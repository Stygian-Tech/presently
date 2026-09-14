import SwiftUI
import UIKit

struct StoryEditorCanvas: UIViewRepresentable {
    let session: StoryEditorSession
    var isEditable: Bool

    func makeUIView(context: Context) -> EditorCanvasView { EditorCanvasView(session: session) }
    func updateUIView(_ view: EditorCanvasView, context: Context) {
        // Reading observable properties here schedules UIKit redraws on model changes.
        view.update(composition: session.composition, selection: session.selectedID, editable: isEditable)
    }
}

@MainActor
final class EditorCanvasView: UIView, UIGestureRecognizerDelegate {
    private let session: StoryEditorSession
    private var images: [UUID: (StoryLayer, UIImage)] = [:]
    private var activeGestures = Set<ObjectIdentifier>()
    private var showVerticalGuide = false
    private var showHorizontalGuide = false
    private var composition = StoryComposition()
    private var selection: UUID?
    private var editable = true
    private var photoRect: CGRect { StoryRenderer.photoRect(imageSize: session.photo.size, bounds: bounds) }

    init(session: StoryEditorSession) {
        self.session = session
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        let gestures: [UIGestureRecognizer] = [
            UITapGestureRecognizer(target: self, action: #selector(tap(_:))),
            UIPanGestureRecognizer(target: self, action: #selector(pan(_:))),
            UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))),
            UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        ]
        for gesture in gestures { gesture.delegate = self; addGestureRecognizer(gesture) }
        accessibilityIdentifier = "storyEditorCanvas"
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(composition: StoryComposition, selection: UUID?, editable: Bool) {
        self.composition = composition
        self.selection = selection
        self.editable = editable
        for layer in composition.layers {
            // Transform-only changes reuse their raster; expensive text layout happens only on content edits.
            var content = layer
            content.x = 0; content.y = 0; content.width = 1; content.rotation = 0
            if images[layer.id]?.0 != content { images[layer.id] = (content, StoryRenderer.layerImage(layer)) }
        }
        images = images.filter { id, _ in composition.layers.contains { $0.id == id } }
        rebuildAccessibility()
        setNeedsDisplay()
    }

    override func layoutSubviews() { super.layoutSubviews(); rebuildAccessibility(); setNeedsDisplay() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let photo = photoRect
        session.photo.draw(in: photo)
        context.saveGState()
        context.clip(to: photo)
        for layer in composition.layers {
            guard let image = images[layer.id]?.1 else { continue }
            StoryRenderer.drawLayer(layer, image: image, photoRect: photo, context: context)
            if editable && selection == layer.id {
                let size = StoryRenderer.layerSize(layer, image: image, photoSize: photo.size)
                context.saveGState()
                context.translateBy(x: photo.minX + photo.width * layer.x, y: photo.minY + photo.height * layer.y)
                context.rotate(by: layer.rotation)
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(1.5)
                context.setLineDash(phase: 0, lengths: [5, 4])
                context.stroke(CGRect(x: -size.width / 2 - 3, y: -size.height / 2 - 3, width: size.width + 6, height: size.height + 6))
                context.restoreGState()
            }
        }
        context.setStrokeColor(UIColor.systemYellow.cgColor)
        context.setLineWidth(1)
        if showVerticalGuide { context.move(to: CGPoint(x: photo.midX, y: photo.minY)); context.addLine(to: CGPoint(x: photo.midX, y: photo.maxY)); context.strokePath() }
        if showHorizontalGuide { context.move(to: CGPoint(x: photo.minX, y: photo.midY)); context.addLine(to: CGPoint(x: photo.maxX, y: photo.midY)); context.strokePath() }
        context.restoreGState()
    }

    private func layer(at point: CGPoint) -> StoryLayer? {
        guard photoRect.contains(point) else { return nil }
        return composition.layers.reversed().first { layer in
            guard let image = images[layer.id]?.1 else { return false }
            let size = StoryRenderer.layerSize(layer, image: image, photoSize: photoRect.size)
            let dx = point.x - (photoRect.minX + photoRect.width * layer.x)
            let dy = point.y - (photoRect.minY + photoRect.height * layer.y)
            let localX = dx * cos(layer.rotation) + dy * sin(layer.rotation)
            let localY = -dx * sin(layer.rotation) + dy * cos(layer.rotation)
            return abs(localX) <= max(22, size.width / 2) && abs(localY) <= max(22, size.height / 2)
        }
    }

    @objc private func tap(_ recognizer: UITapGestureRecognizer) {
        guard editable else { return }
        session.selectedID = layer(at: recognizer.location(in: self))?.id
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard editable else { return false }
        if gestureRecognizer is UITapGestureRecognizer { return true }
        if activeGestures.isEmpty {
            guard let hit = layer(at: gestureRecognizer.location(in: self)) else { return false }
            session.selectedID = hit.id
        }
        return session.selectedID != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        !(gestureRecognizer is UITapGestureRecognizer) && !(otherGestureRecognizer is UITapGestureRecognizer)
    }

    private func track(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == .began {
            activeGestures.insert(ObjectIdentifier(recognizer))
            session.beginTransform()
        }
        if [.ended, .cancelled, .failed].contains(recognizer.state) {
            activeGestures.remove(ObjectIdentifier(recognizer))
            if activeGestures.isEmpty {
                if let layer = session.selectedLayer {
                    session.transform(id: layer.id, x: showVerticalGuide ? 0.5 : nil, y: showHorizontalGuide ? 0.5 : nil)
                }
                session.endTransform()
                showVerticalGuide = false; showHorizontalGuide = false
                setNeedsDisplay()
            }
        }
    }

    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        track(recognizer)
        guard editable, recognizer.state == .began || recognizer.state == .changed,
              let layer = session.selectedLayer, photoRect.width > 0 else { return }
        let delta = recognizer.translation(in: self)
        let x = layer.x + delta.x / photoRect.width
        let y = layer.y + delta.y / photoRect.height
        // Guides snap on gesture completion; incremental pan remains smooth across the center.
        showVerticalGuide = abs(x - 0.5) < 0.012
        showHorizontalGuide = abs(y - 0.5) < 0.012
        session.transform(id: layer.id, x: x, y: y)
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func pinch(_ recognizer: UIPinchGestureRecognizer) {
        track(recognizer)
        guard editable, recognizer.state == .began || recognizer.state == .changed, let layer = session.selectedLayer else { return }
        session.transform(id: layer.id, width: layer.width * recognizer.scale)
        recognizer.scale = 1
    }

    @objc private func rotate(_ recognizer: UIRotationGestureRecognizer) {
        track(recognizer)
        guard editable, recognizer.state == .began || recognizer.state == .changed, let layer = session.selectedLayer else { return }
        session.transform(id: layer.id, rotation: layer.rotation + recognizer.rotation)
        recognizer.rotation = 0
    }

    private func rebuildAccessibility() {
        accessibilityElements = composition.layers.map { layer in
            let element = EditorLayerAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = layer.stickerPNG == nil ? layer.text : "Image sticker"
            element.accessibilityTraits = [.button]
            element.accessibilityHint = "Select to edit, move, resize, rotate, or delete using layer controls"
            let center = CGPoint(x: photoRect.minX + photoRect.width * layer.x, y: photoRect.minY + photoRect.height * layer.y)
            element.accessibilityFrameInContainerSpace = CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60)
            element.activate = { [weak self] in
                guard let self, self.editable else { return false }
                self.session.selectedID = layer.id
                return true
            }
            return element
        }
    }
}

private final class EditorLayerAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}
