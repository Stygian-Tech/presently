import Foundation

enum FlashesStoryContract {
    static let collection = "blue.flashes.story.post"
    static let expiresInMinutes = 1_440
    static let maximumImageBytes = 10_485_760
    static let jpegMIMEType = "image/jpeg"
}

struct ATProtoBlob: Codable, Equatable, Sendable {
    struct Reference: Codable, Equatable, Sendable {
        let link: String

        enum CodingKeys: String, CodingKey {
            case link = "$link"
        }
    }

    let type: String
    let reference: Reference
    let mimeType: String
    let size: Int

    init(cid: String, mimeType: String, size: Int) {
        type = "blob"
        reference = Reference(link: cid)
        self.mimeType = mimeType
        self.size = size
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case reference = "ref"
        case mimeType
        case size
    }
}

struct FlashesStoryRecord: Codable, Equatable, Sendable {
    let type: String
    let image: ATProtoBlob
    let createdAt: String
    let expiresInMinutes: Int

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case image
        case createdAt
        case expiresInMinutes
    }
}

enum FlashesStoryRecordFactory {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func make(blob: ATProtoBlob, createdAt: Date) throws -> FlashesStoryRecord {
        guard blob.mimeType == FlashesStoryContract.jpegMIMEType else {
            throw StoryContractError.unsupportedMIMEType(blob.mimeType)
        }
        guard blob.size <= FlashesStoryContract.maximumImageBytes else {
            throw StoryContractError.imageTooLarge(blob.size)
        }

        return FlashesStoryRecord(
            type: FlashesStoryContract.collection,
            image: blob,
            createdAt: timestampFormatter.string(from: createdAt),
            expiresInMinutes: FlashesStoryContract.expiresInMinutes
        )
    }
}

enum StoryContractError: LocalizedError, Equatable {
    case unsupportedMIMEType(String)
    case imageTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedMIMEType(mimeType):
            "Presently's MVP can only publish JPEG images, not \(mimeType)."
        case let .imageTooLarge(bytes):
            "The image is \(bytes) bytes; Flashes stories allow at most 10 MiB."
        }
    }
}
