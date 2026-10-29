import Foundation

/// The host resolves the PDS and applies its authentication, refresh, and nonce handling.
public protocol StoryPublishingTransport: Sendable {
    func send(_ request: StoryPublishingRequest) async throws -> StoryPublishingResponse
}

public struct StoryPublishingRequest: Sendable {
    public let method: String
    public let procedure: String
    public let queryItems: [URLQueryItem]
    public let body: Data?
    public let contentType: String?

    public init(method: String, procedure: String, queryItems: [URLQueryItem] = [], body: Data? = nil, contentType: String? = nil) {
        self.method = method
        self.procedure = procedure
        self.queryItems = queryItems
        self.body = body
        self.contentType = contentType
    }
}

public struct StoryPublishingResponse: Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public enum StoryPublishingError: Error, Equatable, LocalizedError {
    case profileLookupFailed(Int)
    case profileCreationFailed(Int)
    case existingRecordMismatch

    public var errorDescription: String? {
        switch self {
        case let .profileLookupFailed(status): "The Flashes profile could not be checked (HTTP \(status))."
        case let .profileCreationFailed(status): "The Flashes profile could not be created (HTTP \(status))."
        case .existingRecordMismatch: "This story's record key is already used by a different story."
        }
    }
}

public struct StoryPublisher: Sendable {
    public static let requiredOAuthScopes = [
        "atproto",
        "repo:blue.flashes.actor.profile?action=create",
        "repo:blue.flashes.story.post?action=create",
        "blob:image/jpeg",
    ]

    public let repo: String
    private let transport: any StoryPublishingTransport

    public init(repo: String, transport: any StoryPublishingTransport) {
        self.repo = repo
        self.transport = transport
    }

    /// Preserve existing preferences. Only a confirmed missing self record is created.
    public func ensureActorProfile(createdAt: Date = Date()) async throws {
        let lookup = try await transport.send(getRecord(collection: FlashesActorProfileContract.collection, key: FlashesActorProfileContract.recordKey))
        if lookup.statusCode == 200 { return }
        guard isError(lookup, named: "RecordNotFound") else {
            throw StoryPublishingError.profileLookupFailed(lookup.statusCode)
        }
        let request = CreateRecordRequest(repo: repo, collection: FlashesActorProfileContract.collection, recordKey: FlashesActorProfileContract.recordKey, record: FlashesActorProfileFactory.make(createdAt: createdAt))
        let created = try await transport.send(jsonRequest(body: JSONEncoder().encode(request)))
        guard created.statusCode == 200 || isError(created, named: "RecordAlreadyExists") else {
            throw StoryPublishingError.profileCreationFailed(created.statusCode)
        }
    }

    /// The host retains the same key, date, and JPEG bytes across retries.
    /// Call `ensureActorProfile` before publishing for accounts whose profile is not yet ready.
    public func publish(jpegData: Data, createdAt: Date, recordKey: String) async throws -> PublishedStory {
        guard jpegData.count <= FlashesStoryContract.maximumImageBytes else {
            throw StoryContractError.imageTooLarge(jpegData.count)
        }
        let upload = try await transport.send(StoryPublishingRequest(method: "POST", procedure: "com.atproto.repo.uploadBlob", body: jpegData, contentType: FlashesStoryContract.jpegMIMEType))
        guard upload.statusCode == 200 else { throw StoryContractError.uploadFailed(upload.statusCode) }
        guard let uploaded = try? JSONDecoder().decode(UploadBlobResponse.self, from: upload.data),
              uploaded.blob.type == "blob", !uploaded.blob.reference.link.isEmpty,
              uploaded.blob.mimeType == FlashesStoryContract.jpegMIMEType,
              uploaded.blob.size == jpegData.count else { throw StoryContractError.invalidBlobResponse }
        let record = try FlashesStoryRecordFactory.make(blob: uploaded.blob, createdAt: createdAt)
        let request = CreateRecordRequest(repo: repo, collection: FlashesStoryContract.collection, recordKey: recordKey, record: record)
        let created = try await transport.send(jsonRequest(body: JSONEncoder().encode(request)))
        let expectedURI = "at://\(repo)/\(FlashesStoryContract.collection)/\(recordKey)"
        if isError(created, named: "RecordAlreadyExists") {
            let lookup = try await transport.send(getRecord(collection: FlashesStoryContract.collection, key: recordKey))
            guard lookup.statusCode == 200,
                  let existing = try? JSONDecoder().decode(ExistingStory.self, from: lookup.data),
                  existing.uri == expectedURI, !existing.cid.isEmpty,
                  existing.value == record else { throw StoryPublishingError.existingRecordMismatch }
            return PublishedStory(uri: existing.uri, cid: existing.cid)
        }
        guard created.statusCode == 200 else { throw StoryContractError.createRecordFailed(created.statusCode) }
        guard let response = try? JSONDecoder().decode(CreateRecordResponse.self, from: created.data),
              response.uri == expectedURI, !response.cid.isEmpty else { throw StoryContractError.invalidCreateRecordResponse }
        return PublishedStory(uri: response.uri, cid: response.cid)
    }

    private func getRecord(collection: String, key: String) -> StoryPublishingRequest {
        StoryPublishingRequest(method: "GET", procedure: "com.atproto.repo.getRecord", queryItems: [URLQueryItem(name: "repo", value: repo), URLQueryItem(name: "collection", value: collection), URLQueryItem(name: "rkey", value: key)])
    }

    private func jsonRequest(body: Data) -> StoryPublishingRequest {
        StoryPublishingRequest(method: "POST", procedure: "com.atproto.repo.createRecord", body: body, contentType: "application/json")
    }

    private func isError(_ response: StoryPublishingResponse, named name: String) -> Bool {
        guard response.statusCode == 400,
              let error = try? JSONDecoder().decode(ProtocolError.self, from: response.data) else { return false }
        return error.error == name
    }
}

private struct ProtocolError: Decodable { let error: String }
private struct ExistingStory: Decodable {
    let uri: String
    let cid: String
    let value: FlashesStoryRecord
}
