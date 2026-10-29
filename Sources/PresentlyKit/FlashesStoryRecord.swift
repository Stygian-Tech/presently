import Foundation

public enum FlashesStoryContract {
    public static let collection = "blue.flashes.story.post"
    public static let expiresInMinutes = 1_440
    public static let maximumImageBytes = 10_485_760
    public static let jpegMIMEType = "image/jpeg"
}

public struct ATProtoBlob: Codable, Equatable, Sendable {
    public struct Reference: Codable, Equatable, Sendable {
        public let link: String

        public init(link: String) { self.link = link }

        enum CodingKeys: String, CodingKey {
            case link = "$link"
        }
    }

    public let type: String
    public let reference: Reference
    public let mimeType: String
    public let size: Int

    public init(cid: String, mimeType: String, size: Int) {
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

public struct FlashesStoryRecord: Codable, Equatable, Sendable {
    public let type: String
    public let image: ATProtoBlob
    public let createdAt: String
    public let expiresInMinutes: Int

    public init(type: String = FlashesStoryContract.collection, image: ATProtoBlob, createdAt: String, expiresInMinutes: Int = FlashesStoryContract.expiresInMinutes) {
        self.type = type
        self.image = image
        self.createdAt = createdAt
        self.expiresInMinutes = expiresInMinutes
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case image
        case createdAt
        case expiresInMinutes
    }
}

public enum FlashesStoryRecordFactory {
    private static func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    public static func make(blob: ATProtoBlob, createdAt: Date) throws -> FlashesStoryRecord {
        guard blob.mimeType == FlashesStoryContract.jpegMIMEType else {
            throw StoryContractError.unsupportedMIMEType(blob.mimeType)
        }
        guard blob.size <= FlashesStoryContract.maximumImageBytes else {
            throw StoryContractError.imageTooLarge(blob.size)
        }

        return FlashesStoryRecord(
            type: FlashesStoryContract.collection,
            image: blob,
            createdAt: timestampFormatter().string(from: createdAt),
            expiresInMinutes: FlashesStoryContract.expiresInMinutes
        )
    }
}

public struct UploadBlobResponse: Decodable, Equatable, Sendable {
    public let blob: ATProtoBlob

    public init(blob: ATProtoBlob) { self.blob = blob }
}

public struct CreateRecordResponse: Decodable, Equatable, Sendable {
    public let uri: String
    public let cid: String

    public init(uri: String, cid: String) { self.uri = uri; self.cid = cid }
}

public struct PublishedStory: Equatable, Sendable {
    public let uri: String
    public let cid: String?

    public init(uri: String, cid: String?) { self.uri = uri; self.cid = cid }
}

public enum ATProtoTID {
    private static let alphabet = Array("234567abcdefghijklmnopqrstuvwxyz")

    public static func make(
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

public enum StoryContractError: LocalizedError, Equatable {
    case unsupportedMIMEType(String)
    case imageTooLarge(Int)
    case invalidBlobResponse
    case uploadFailed(Int)
    case createRecordFailed(Int)
    case invalidCreateRecordResponse

    public var errorDescription: String? {
        switch self {
        case let .unsupportedMIMEType(mimeType):
            "Stories can only publish JPEG images, not \(mimeType)."
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
