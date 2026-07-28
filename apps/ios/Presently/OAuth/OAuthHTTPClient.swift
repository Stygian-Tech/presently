import Foundation

struct OAuthHTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let headers: [String: String]

    var dpopNonce: String? {
        headers.first {
            $0.key.caseInsensitiveCompare("DPoP-Nonce") == .orderedSame
        }?.value
    }
}

struct OAuthHTTPClient: Sendable {
    private let session: URLSession

    init(session: URLSession = OAuthHTTPClient.makeSession()) {
        self.session = session
    }

    func get(
        _ url: URL,
        headers: [String: String] = [:]
    ) async throws -> OAuthHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await send(request)
    }

    func getJSON<Value: Decodable>(_ url: URL) async throws -> Value {
        let response = try await get(
            url,
            headers: ["Accept": "application/json"]
        )
        guard response.statusCode == 200,
              Self.contentTypeIsJSON(response.headers) else {
            throw OAuthValidationError.unexpectedResponse(response.statusCode)
        }
        return try JSONDecoder().decode(Value.self, from: response.data)
    }

    func postForm(
        _ url: URL,
        fields: [URLQueryItem],
        headers: [String: String]
    ) async throws -> OAuthHTTPResponse {
        var components = URLComponents()
        components.queryItems = fields
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await send(request)
    }

    func postJSON(
        _ url: URL,
        body: Data,
        headers: [String: String]
    ) async throws -> OAuthHTTPResponse {
        try await post(
            url,
            body: body,
            contentType: "application/json",
            headers: headers
        )
    }

    func post(
        _ url: URL,
        body: Data,
        contentType: String,
        headers: [String: String]
    ) async throws -> OAuthHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> OAuthHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OAuthValidationError.invalidAuthorizationServerMetadata
        }
        return OAuthHTTPResponse(
            data: data,
            statusCode: response.statusCode,
            headers: response.allHeaderFields.reduce(into: [:]) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            }
        )
    }

    static func contentTypeIsJSON(_ headers: [String: String]) -> Bool {
        let value = headers.first {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value.lowercased()
        guard let mediaType = value?.split(separator: ";").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return mediaType == "application/json" || mediaType.hasSuffix("+json")
    }

    private static func makeSession() -> URLSession {
        URLSession(
            configuration: .ephemeral,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
