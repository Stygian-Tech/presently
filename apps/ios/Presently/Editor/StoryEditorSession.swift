import Observation
import UIKit

@MainActor @Observable
final class StoryEditorSession {
    let photo: UIImage
    private(set) var composition: StoryComposition
    var selectedID: UUID?
    var isImporting = false
    private(set) var undoStack: [StoryComposition] = []
    private var gestureStart: StoryComposition?
    var onChange: ((StoryComposition) -> Void)?

    init(photoData: Data, recipe: Data?) throws {
        photo = try StoryRenderer.uprightImage(photoData)
        composition = try StoryComposition.decode(recipe)
    }

    var selectedLayer: StoryLayer? { composition.layers.first { $0.id == selectedID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var isTransforming: Bool { gestureStart != nil }
    var canFinishEditing: Bool { !isImporting && !isTransforming }

    func add(_ layer: StoryLayer) throws {
        guard composition.layers.count < 30 else { throw EditorError.tooManyLayers }
        var proposed = composition
        proposed.layers.append(layer)
        guard proposed.fitsAssetBudget else { throw EditorError.imageTooLarge }
        checkpoint()
        composition = proposed
        selectedID = layer.id
        onChange?(composition)
    }

    func update(_ layer: StoryLayer) {
        guard let index = composition.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        checkpoint()
        composition.layers[index] = layer
        onChange?(composition)
    }

    func deleteSelected() {
        guard let selectedID else { return }
        checkpoint()
        composition.layers.removeAll { $0.id == selectedID }
        self.selectedID = nil
        onChange?(composition)
    }

    func bringToFront() {
        guard let layer = selectedLayer else { return }
        checkpoint()
        composition.layers.removeAll { $0.id == layer.id }
        composition.layers.append(layer)
        onChange?(composition)
    }

    func beginTransform() {
        if gestureStart == nil { gestureStart = composition }
    }

    func transform(id: UUID, x: Double? = nil, y: Double? = nil, width: Double? = nil, rotation: Double? = nil) {
        guard gestureStart != nil else { return }
        guard let index = composition.layers.firstIndex(where: { $0.id == id }) else { return }
        if let x { composition.layers[index].x = min(1, max(0, x)) }
        if let y { composition.layers[index].y = min(1, max(0, y)) }
        if let width { composition.layers[index].width = min(1.5, max(0.08, width)) }
        if let rotation { composition.layers[index].rotation = rotation.truncatingRemainder(dividingBy: .pi * 2) }
    }

    func endTransform() {
        guard let start = gestureStart else { return }
        gestureStart = nil
        if start != composition { appendUndo(start); onChange?(composition) }
    }

    func undo() {
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
