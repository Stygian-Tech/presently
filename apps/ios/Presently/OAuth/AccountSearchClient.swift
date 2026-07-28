import Foundation

struct AccountSuggestion: Decodable, Equatable, Identifiable, Sendable {
    let did: String
    let handle: String
    let displayName: String?
    let avatar: URL?

    var id: String { did }
}

struct AccountSuggestionsResponse: Decodable, Equatable, Sendable {
    let actors: [AccountSuggestion]
}

enum AccountSearchError: Error {
    case invalidURL
}

struct AccountSearchClient: Sendable {
    private static let endpoint = URL(
        string: "https://public.api.bsky.app/xrpc/app.bsky.actor.searchActorsTypeahead"
    )!

    private let http: OAuthHTTPClient

    init(http: OAuthHTTPClient = OAuthHTTPClient()) {
        self.http = http
    }

    func suggestions(for query: String, limit: Int = 6) async throws
        -> [AccountSuggestion] {
        let response: AccountSuggestionsResponse = try await http.getJSON(
            Self.requestURL(for: query, limit: limit)
        )
        return response.actors
    }

    static func requestURL(for query: String, limit: Int = 6) throws -> URL {
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw AccountSearchError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components.url else {
            throw AccountSearchError.invalidURL
        }
        return url
    }
}
