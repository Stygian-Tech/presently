import Foundation
import SwiftData

@Model
final class LocalStoryDraft {
    enum State: String, Codable {
        case pending
        case publishing
        case failed
        case published
    }

    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var imageData: Data
    @Attribute(.externalStorage) var originalImageData: Data?
    @Attribute(.externalStorage) var editorData: Data?
    var createdAt: Date
    var stateRawValue: String
    var lastError: String?
    var publishedURI: String?
    var publishedCID: String?
    var recordKey: String?

    var state: State {
        get { State(rawValue: stateRawValue) ?? .pending }
        set { stateRawValue = newValue.rawValue }
    }

    /// Older pending and locked-camera drafts only stored imageData. Preserve it
    /// before the first export so restoring never applies layers to a flattened photo.
    func preserveOriginalForEditing() {
        if originalImageData == nil { originalImageData = imageData }
    }

    init(
        id: UUID = UUID(),
        imageData: Data,
        createdAt: Date = Date(),
        state: State = .pending,
        recordKey: String? = nil
    ) {
        self.id = id
        self.imageData = imageData
        self.createdAt = createdAt
        stateRawValue = state.rawValue
        self.recordKey = recordKey
    }
}
