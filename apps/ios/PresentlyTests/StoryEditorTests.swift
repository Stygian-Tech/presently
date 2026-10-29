import SwiftData
import Testing
import UIKit
import PresentlyKit
@testable import Presently

@MainActor
struct StoryDraftIntegrationTests {
    private func solid(_ color: UIColor, size: CGSize = CGSize(width: 200, height: 400)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
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

}
