import ImageIO
import SwiftData
import SwiftUI
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Presently

@MainActor
struct StoryEditorTests {
    private func solid(_ color: UIColor, size: CGSize = CGSize(width: 200, height: 400)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func letterboxedGeometryUsesPhotoNotScreen() {
        let rect = StoryRenderer.photoRect(imageSize: CGSize(width: 400, height: 200), bounds: CGRect(x: 0, y: 0, width: 300, height: 600))
        #expect(rect == CGRect(x: 0, y: 225, width: 300, height: 150))
        let portrait = StoryRenderer.photoRect(imageSize: CGSize(width: 200, height: 400), bounds: CGRect(x: 0, y: 0, width: 300, height: 600))
        #expect(portrait == CGRect(x: 0, y: 0, width: 300, height: 600))
    }

    @Test func transformsAreBoundedUndoableAndPersistOncePerGesture() throws {
        let session = try StoryEditorSession(photoData: #require(solid(.blue).pngData()), recipe: nil)
        let layer = StoryLayer(text: "Hello")
        try session.add(layer)
        var persisted: [StoryComposition] = []
        session.onChange = { persisted.append($0) }
        #expect(session.canFinishEditing)
        session.beginTransform()
        #expect(!session.canFinishEditing)
        session.beginTransform()
        session.transform(id: layer.id, x: -2, y: 3, width: 20, rotation: .pi * 5)
        session.transform(id: layer.id, x: 0.4, y: 0.6)
        #expect(persisted.isEmpty)
        session.endTransform()
        #expect(persisted.count == 1)
        #expect(session.canFinishEditing)
        let ended = session.composition
        session.transform(id: layer.id, x: 0.9)
        #expect(session.composition == ended)
        #expect(session.selectedLayer?.width == 1.5)
        #expect(session.selectedLayer?.rotation == .pi)
        session.undo()
        #expect(session.composition.layers == [layer])
        #expect(persisted.count == 2)
    }

    @Test func textStyleAndTransparentStickerRoundTrip() throws {
        var text = StoryLayer(text: "Two lines\nHello 🌈")
        text.style = .mono; text.color = "pink"; text.background = true; text.alignment = .right
        text.x = 0.25; text.rotation = 0.35
        let stickerData: Data = try #require(solid(.clear, size: CGSize(width: 10, height: 20)).pngData())
        let sticker = StoryLayer(stickerPNG: stickerData)
        let composition = StoryComposition(layers: [text, sticker])
        #expect(try StoryComposition.decode(composition.encoded()) == composition)
        var future = composition
        future.version = 99
        #expect(throws: EditorError.self) { try StoryComposition.decode(future.encoded()) }
    }

    @Test func compositePreservesTransparencyStackingAndOutputSize() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let sticker = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        }
        let stickerData: Data = try #require(sticker.pngData())
        var layer = StoryLayer(stickerPNG: stickerData)
        layer.width = 0.5
        let photo = solid(.blue)
        let rendered = StoryRenderer.render(photo: photo, composition: StoryComposition(layers: [layer]))
        #expect(rendered.size == photo.size)
        #expect(pixel(rendered, x: 70, y: 200).blue > 250)
        #expect(pixel(rendered, x: 120, y: 200).red > 250)
        let topData: Data = try #require(solid(.green, size: CGSize(width: 10, height: 10)).pngData())
        var top = StoryLayer(stickerPNG: topData)
        top.width = 0.1
        let stacked = StoryRenderer.render(photo: photo, composition: StoryComposition(layers: [layer, top]))
        #expect(pixel(stacked, x: 100, y: 200).green > 250)
        let jpeg = try StoryRenderer.jpeg(photo: photo, composition: StoryComposition(layers: [layer]))
        #expect(jpeg.count < FlashesStoryContract.maximumImageBytes)
        #expect(UIImage(data: jpeg)?.size == photo.size)
    }

    @Test func importedEXIFOrientationIsAppliedBeforeGeometry() throws {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(solid(.red, size: CGSize(width: 80, height: 40)).cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let image = try StoryRenderer.uprightImage(data as Data)
        #expect(image.imageOrientation == .up)
        #expect(image.size == CGSize(width: 40, height: 80))
    }

    @Test func aggregateDecodedStickerBudgetPreventsUnboundedCanvasMemory() throws {
        let data = try #require(solid(.blue, size: CGSize(width: 1024, height: 1024)).pngData())
        let session = try StoryEditorSession(photoData: #require(solid(.white).pngData()), recipe: nil)
        for _ in 0..<6 { try session.add(StoryLayer(stickerPNG: data)) }
        #expect(throws: EditorError.self) { try session.add(StoryLayer(stickerPNG: data)) }
        #expect(session.composition.layers.count == 6)
        #expect(!StoryComposition(layers: (0..<7).map { _ in StoryLayer(stickerPNG: data) }).fitsAssetBudget)
    }

    @Test func legacyDraftPreservesOriginalAcrossExportAndStoreReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("store")
        defer { for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let configuration = ModelConfiguration(url: url)
        let original = try #require(solid(.blue).jpegData(compressionQuality: 0.9))
        let recipe = StoryComposition(layers: [StoryLayer(text: "Saved draft")])
        let exported: Data
        do {
            let container = try ModelContainer(for: LocalStoryDraft.self, configurations: configuration)
            let context = ModelContext(container)
            let draft = LocalStoryDraft(imageData: original)
            draft.preserveOriginalForEditing()
            let session = try StoryEditorSession(photoData: #require(draft.originalImageData), recipe: nil)
            exported = try StoryRenderer.jpeg(photo: session.photo, composition: recipe)
            draft.imageData = exported
            draft.editorData = try recipe.encoded()
            draft.recordKey = "stable-retry-key"
            draft.state = .failed
            context.insert(draft)
            try context.save()
        }
        let reopened = try ModelContainer(for: LocalStoryDraft.self, configurations: configuration)
        let context = ModelContext(reopened)
        let draft = try #require(context.fetch(FetchDescriptor<LocalStoryDraft>()).first)
        #expect(draft.originalImageData == original)
        #expect(draft.imageData == exported)
        #expect(draft.recordKey == "stable-retry-key")
        let restored = try StoryEditorSession(photoData: #require(draft.originalImageData), recipe: draft.editorData)
        #expect(restored.composition == recipe)
        #expect(try StoryRenderer.jpeg(photo: restored.photo, composition: restored.composition) == exported)
    }

    @Test func emojiRasterFillsStickerBoxAndLongTextRasterIsBounded() {
        let emoji = StoryRenderer.layerImage(StoryLayer(text: "🌈", isEmoji: true))
        #expect(emoji.size == CGSize(width: 160, height: 160))
        let long = StoryRenderer.layerImage(StoryLayer(text: String(repeating: "a\n", count: 250)))
        #expect(long.size.height <= 1024)
        #expect(long.size.width <= 1024)
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let width = Int(image.size.width), height = Int(image.size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}

@MainActor
struct StoryTextInputTests {
    @Test func staleSwiftUISnapshotsDoNotReplaceNativeRapidInputOrCaret() {
        var model = ""
        let input = StoryTextInput(text: Binding(get: { model }, set: { model = $0 }), onSticker: { _ in }, onError: { _ in })
        let coordinator = input.makeCoordinator()
        let view = EditorTestTextView()
        view.pretendFirstResponder = true
        view.delegate = coordinator
        for character in "A little more present" {
            let staleSnapshot = model
            view.insertText(String(character))
            coordinator.textViewDidChange(view)
            coordinator.synchronize(view, modelText: staleSnapshot)
            #expect(view.text == model)
            #expect(view.selectedRange == NSRange(location: model.utf16.count, length: 0))
        }
        #expect(view.text == "A little more present")
        #expect(model == "A little more present")
    }

    @Test func markedCompositionStaysNativeUntilCommit() {
        var model = "Before "
        let input = StoryTextInput(text: Binding(get: { model }, set: { model = $0 }), onSticker: { _ in }, onError: { _ in })
        let coordinator = input.makeCoordinator()
        let view = EditorTestTextView()
        view.text = "Before にほん"
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        view.pretendMarkedText = true
        coordinator.textViewDidChange(view)
        coordinator.synchronize(view, modelText: model)
        #expect(view.text == "Before にほん")
        #expect(model == "Before ")
        view.pretendMarkedText = false
        view.text = "Before 日本"
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        coordinator.textViewDidChange(view)
        #expect(model == "Before 日本")
    }

    @Test func saveReadsLatestNativeTextBeforeBindingEchoAndCommitsIME() {
        var model = "Hello"
        let handle = StoryTextInputHandle()
        let input = StoryTextInput(text: Binding(get: { model }, set: { model = $0 }), handle: handle, onSticker: { _ in }, onError: { _ in })
        let coordinator = input.makeCoordinator()
        let view = EditorTestTextView()
        view.text = "Hello Presently"
        view.pretendMarkedText = true
        handle.textView = view
        handle.coordinator = coordinator
        #expect(handle.committedText() == "Hello Presently")
        #expect(!view.pretendMarkedText)
        #expect(model == "Hello Presently")
    }

    @Test func externalChangesPreserveSelectionWhenNativeEditorIsInactive() {
        let input = StoryTextInput(text: .constant(""), onSticker: { _ in }, onError: { _ in })
        let coordinator = input.makeCoordinator()
        let view = EditorTestTextView()
        view.text = "Original text"
        view.selectedRange = NSRange(location: 3, length: 4)
        coordinator.synchronize(view, modelText: "Replacement text")
        #expect(view.text == "Replacement text")
        #expect(view.selectedRange == NSRange(location: 3, length: 4))
        coordinator.synchronize(view, modelText: "Hi")
        #expect(view.selectedRange == NSRange(location: 2, length: 0))
    }
}

@MainActor
private final class EditorTestTextView: UITextView {
    var pretendFirstResponder = false
    var pretendMarkedText = false
    override var isFirstResponder: Bool { pretendFirstResponder }
    override var markedTextRange: UITextRange? { pretendMarkedText ? selectedTextRange : nil }
    override func unmarkText() { pretendMarkedText = false; super.unmarkText() }
}
