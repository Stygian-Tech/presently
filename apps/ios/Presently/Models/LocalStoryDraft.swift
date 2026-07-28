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
