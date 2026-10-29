import Observation
import UIKit

@MainActor @Observable
public final class StoryEditorSession {
    public let photo: UIImage
    public private(set) var composition: StoryComposition
    public var selectedID: UUID?
    public var isImporting = false
    public private(set) var undoStack: [StoryComposition] = []
    private var gestureStart: StoryComposition?
    public var onChange: ((StoryComposition) -> Void)?

    public init(photoData: Data, recipe: Data?) throws {
        let composition = try StoryComposition.decode(recipe)
        let original = try StoryRenderer.uprightImage(photoData)
        photo = composition.usesStoryCrop == true ? try StoryRenderer.storyCrop(original, viewportAspectRatio: composition.captureViewportAspectRatio) : original
        self.composition = composition
    }

    public var selectedLayer: StoryLayer? { composition.layers.first { $0.id == selectedID } }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var isTransforming: Bool { gestureStart != nil }
    public var canFinishEditing: Bool { !isImporting && !isTransforming }

    public func add(_ layer: StoryLayer) throws {
        guard composition.layers.count < 30 else { throw EditorError.tooManyLayers }
        var proposed = composition
        proposed.layers.append(layer)
        guard proposed.fitsAssetBudget else { throw EditorError.imageTooLarge }
        checkpoint()
        composition = proposed
        selectedID = layer.id
        onChange?(composition)
    }

    public func update(_ layer: StoryLayer) {
        guard let index = composition.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        checkpoint()
        composition.layers[index] = layer
        onChange?(composition)
    }

    public func deleteSelected() {
        guard let selectedID else { return }
        checkpoint()
        composition.layers.removeAll { $0.id == selectedID }
        self.selectedID = nil
        onChange?(composition)
    }

    public func bringToFront() {
        guard let layer = selectedLayer else { return }
        checkpoint()
        composition.layers.removeAll { $0.id == layer.id }
        composition.layers.append(layer)
        onChange?(composition)
    }

    public func beginTransform() {
        if gestureStart == nil { gestureStart = composition }
    }

    public func transform(id: UUID, x: Double? = nil, y: Double? = nil, width: Double? = nil, rotation: Double? = nil) {
        guard gestureStart != nil else { return }
        guard let index = composition.layers.firstIndex(where: { $0.id == id }) else { return }
        if let x { composition.layers[index].x = min(1, max(0, x)) }
        if let y { composition.layers[index].y = min(1, max(0, y)) }
        if let width { composition.layers[index].width = min(1.5, max(0.08, width)) }
        if let rotation { composition.layers[index].rotation = rotation.truncatingRemainder(dividingBy: .pi * 2) }
    }

    public func endTransform() {
        guard let start = gestureStart else { return }
        gestureStart = nil
        if start != composition { appendUndo(start); onChange?(composition) }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        composition = previous
        selectedID = nil
        onChange?(composition)
    }

    private func checkpoint() { appendUndo(composition) }
    private func appendUndo(_ value: StoryComposition) {
        undoStack.append(value)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }
}
