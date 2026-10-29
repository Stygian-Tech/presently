import Foundation

public enum FlashesActorProfileContract {
    public static let collection = "blue.flashes.actor.profile"
    public static let recordKey = "self"
}

public struct FlashesActorProfile: Codable, Equatable, Sendable {
    public let type: String
    public let createdAt: String
    public let showFeeds: Bool
    public let showLikes: Bool
    public let showLists: Bool
    public let showMedia: Bool
    public let mediaLayout: String
    public let enablePortfolio: Bool
    public let portfolioLayout: String
    public let allowRawDownload: Bool

    public init(type: String = FlashesActorProfileContract.collection, createdAt: String, showFeeds: Bool = true, showLikes: Bool = false, showLists: Bool = true, showMedia: Bool = true, mediaLayout: String = "grid", enablePortfolio: Bool = false, portfolioLayout: String = "grid", allowRawDownload: Bool = false) {
        self.type = type
        self.createdAt = createdAt
        self.showFeeds = showFeeds
        self.showLikes = showLikes
        self.showLists = showLists
        self.showMedia = showMedia
        self.mediaLayout = mediaLayout
        self.enablePortfolio = enablePortfolio
        self.portfolioLayout = portfolioLayout
        self.allowRawDownload = allowRawDownload
    }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case createdAt
        case showFeeds
        case showLikes
        case showLists
        case showMedia
        case mediaLayout
        case enablePortfolio
        case portfolioLayout
        case allowRawDownload
    }
}

public enum FlashesActorProfileFactory {
    private static func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    public static func make(createdAt: Date) -> FlashesActorProfile {
        FlashesActorProfile(
            type: FlashesActorProfileContract.collection,
            createdAt: timestampFormatter().string(from: createdAt),
            showFeeds: true,
            showLikes: false,
            showLists: true,
            showMedia: true,
            mediaLayout: "grid",
            enablePortfolio: false,
            portfolioLayout: "grid",
            allowRawDownload: false
        )
    }
}

public struct CreateRecordRequest<Record: Encodable>: Encodable {
    public let repo: String
    public let collection: String
    public let recordKey: String
    public let record: Record

    public init(repo: String, collection: String, recordKey: String, record: Record) {
        self.repo = repo
        self.collection = collection
        self.recordKey = recordKey
        self.record = record
    }

    enum CodingKeys: String, CodingKey {
        case repo
        case collection
        case recordKey = "rkey"
        case record
    }
}
