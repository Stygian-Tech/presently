import Foundation

enum FlashesActorProfileContract {
    static let collection = "blue.flashes.actor.profile"
    static let recordKey = "self"
}

struct FlashesActorProfile: Codable, Equatable, Sendable {
    let type: String
    let createdAt: String
    let showFeeds: Bool
    let showLikes: Bool
    let showLists: Bool
    let showMedia: Bool
    let mediaLayout: String
    let enablePortfolio: Bool
    let portfolioLayout: String
    let allowRawDownload: Bool

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

enum FlashesActorProfileFactory {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func make(createdAt: Date) -> FlashesActorProfile {
        FlashesActorProfile(
            type: FlashesActorProfileContract.collection,
            createdAt: timestampFormatter.string(from: createdAt),
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

struct CreateRecordRequest<Record: Encodable>: Encodable {
    let repo: String
    let collection: String
    let recordKey: String
    let record: Record

    enum CodingKeys: String, CodingKey {
        case repo
        case collection
        case recordKey = "rkey"
        case record
    }
}
