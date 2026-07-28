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

struct UploadBlobResponse: Decodable, Equatable, Sendable {
    let blob: ATProtoBlob
}

struct CreateRecordResponse: Decodable, Equatable, Sendable {
    let uri: String
    let cid: String
}

struct PublishedStory: Equatable, Sendable {
    let uri: String
    let cid: String?
}

enum ATProtoTID {
    private static let alphabet = Array("234567abcdefghijklmnopqrstuvwxyz")

    static func make(
        date: Date = Date(),
        clockIdentifier: UInt16 = UInt16.random(in: 0..<1_024)
    ) -> String {
        let microseconds = UInt64(
            max(0, date.timeIntervalSince1970 * 1_000_000)
        )
        var value = (microseconds << 10) | UInt64(clockIdentifier & 0x03ff)
        var characters = Array(repeating: Character("2"), count: 13)
        for index in stride(from: 12, through: 0, by: -1) {
            characters[index] = alphabet[Int(value & 0x1f)]
            value >>= 5
        }
        return String(characters)
    }
}

enum StoryContractError: LocalizedError, Equatable {
    case unsupportedMIMEType(String)
    case imageTooLarge(Int)
    case invalidBlobResponse
    case uploadFailed(Int)
    case createRecordFailed(Int)
    case invalidCreateRecordResponse

    var errorDescription: String? {
        switch self {
        case let .unsupportedMIMEType(mimeType):
            "Presently's MVP can only publish JPEG images, not \(mimeType)."
        case let .imageTooLarge(bytes):
            "The image is \(bytes) bytes; Flashes stories allow at most 10 MiB."
        case .invalidBlobResponse:
            "The photo server returned an invalid upload response."
        case let .uploadFailed(status):
            "The photo upload failed with HTTP \(status)."
        case let .createRecordFailed(status):
            "The story could not be created (HTTP \(status))."
        case .invalidCreateRecordResponse:
            "The photo server returned an invalid story response."
        }
    }
}
