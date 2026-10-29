import PresentlyKit
import SwiftUI
import Testing
import UIKit

@MainActor
struct PublicAPITests {
    @Test func hostCanCreateEditPersistRestoreAndExport() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 320)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 320))
        }
        let original = try #require(photo.pngData())
        let recipe = try StoryComposition(usesStoryCrop: true, captureViewportAspectRatio: 9.0 / 16).encoded()
        let session = try StoryEditorSession(photoData: original, recipe: recipe)
        var persisted: Data?
        session.onChange = { persisted = try? $0.encoded() }
        try session.add(StoryLayer(text: "From any host", style: .rounded))
        let persistedRecipe = try #require(persisted)
        let restored = try StoryEditorSession(photoData: original, recipe: persistedRecipe)
        #expect(restored.composition == session.composition)
        let jpeg = try StoryRenderer.jpeg(photo: restored.photo, composition: restored.composition, maximumBytes: 1_000_000)
        #expect(jpeg.count <= 1_000_000)
        #expect(UIImage(data: jpeg)?.size == restored.photo.size)
        _ = StoryEditorView(session: session, onError: { _ in })
        let camera = CameraController()
        _ = CameraViewfinder(camera: camera, onCapture: { _ in })
        _ = CameraPreview(session: camera.session, isCaptureEnabled: false, onCapture: {})
    }

    @Test func exportHonorsHostBudget() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { _ in }
        for budget in [-1, 0, 1] {
            #expect(throws: EditorError.self) {
                try StoryRenderer.jpeg(photo: photo, composition: StoryComposition(), maximumBytes: budget)
            }
        }
    }
}
