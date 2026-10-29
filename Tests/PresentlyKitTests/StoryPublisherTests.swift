import Foundation
import Testing
@testable import PresentlyKit

private actor PublishingTransport: StoryPublishingTransport {
    var responses: [StoryPublishingResponse]
    var requests: [StoryPublishingRequest] = []
    init(_ responses: [StoryPublishingResponse]) { self.responses = responses }
    func send(_ request: StoryPublishingRequest) async throws -> StoryPublishingResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw StubError.exhausted }
        return responses.removeFirst()
    }
    enum StubError: Error { case exhausted }
}

struct StoryPublisherTests {
    private let repo = "did:plc:example"
    private let key = "3jzfcijpj2z2a"
    private let date = Date(timeIntervalSince1970: 1_753_488_000)
    private let photo = Data([1, 2, 3])
    private var uri: String { "at://\(repo)/blue.flashes.story.post/\(key)" }
    private var blob: ATProtoBlob { ATProtoBlob(cid: "bafkreiphoto", mimeType: "image/jpeg", size: photo.count) }
    private func response(_ status: Int, _ json: String) -> StoryPublishingResponse {
        StoryPublishingResponse(statusCode: status, data: Data(json.utf8))
    }
    private func upload(_ blob: ATProtoBlob? = nil) throws -> StoryPublishingResponse {
        let value = try JSONEncoder().encode(blob ?? self.blob)
        let data = Data("{\"blob\":".utf8) + value + Data("}".utf8)
        return StoryPublishingResponse(statusCode: 200, data: data)
    }
    private var success: StoryPublishingResponse { response(200, "{\"uri\":\"\(uri)\",\"cid\":\"bafyrecord\"}") }
    private var conflict: StoryPublishingResponse { response(400, #"{"error":"RecordAlreadyExists"}"#) }
    private var missing: StoryPublishingResponse { response(400, #"{"error":"RecordNotFound"}"#) }

    @Test func publishesUploadThenExactCreateRequest() async throws {
        let transport = PublishingTransport([try upload(), success])
        let published = try await StoryPublisher(repo: repo, transport: transport).publish(jpegData: photo, createdAt: date, recordKey: key)
        #expect(published == PublishedStory(uri: uri, cid: "bafyrecord"))
        let requests = await transport.requests
        #expect(requests.map(\.procedure) == ["com.atproto.repo.uploadBlob", "com.atproto.repo.createRecord"])
        #expect(requests[0].method == "POST")
        #expect(requests[0].body == photo)
        #expect(requests[0].contentType == "image/jpeg")
        let body = try #require(requests[1].body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["repo"] as? String == repo)
        #expect(json["rkey"] as? String == key)
        let record = try #require(json["record"] as? [String: Any])
        #expect(record["createdAt"] as? String == "2025-07-26T00:00:00.000Z")
        #expect(record["expiresInMinutes"] as? Int == 1440)
    }

    @Test func preservesExistingActorProfile() async throws {
        let transport = PublishingTransport([response(200, "{}")])
        try await StoryPublisher(repo: repo, transport: transport).ensureActorProfile()
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].method == "GET")
        #expect(requests[0].queryItems == [URLQueryItem(name: "repo", value: repo), URLQueryItem(name: "collection", value: "blue.flashes.actor.profile"), URLQueryItem(name: "rkey", value: "self")])
    }

    @Test(arguments: [false, true]) func createsMissingActorProfileAndAcceptsCreationRace(race: Bool) async throws {
        let transport = PublishingTransport([missing, race ? conflict : response(200, "{}")])
        try await StoryPublisher(repo: repo, transport: transport).ensureActorProfile(createdAt: date)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let body = try #require(requests[1].body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["collection"] as? String == "blue.flashes.actor.profile")
        #expect(json["rkey"] as? String == "self")
        let record = try #require(json["record"] as? [String: Any])
        #expect(record["showLikes"] as? Bool == false)
        #expect(record["mediaLayout"] as? String == "grid")
        #expect(record["createdAt"] as? String == "2025-07-26T00:00:00.000Z")
    }

    @Test(arguments: [400, 404, 500]) func refusesUnconfirmedMissingProfile(status: Int) async throws {
        let transport = PublishingTransport([response(status, #"{"error":"Unknown"}"#)])
        await #expect(throws: StoryPublishingError.profileLookupFailed(status)) {
            try await StoryPublisher(repo: repo, transport: transport).ensureActorProfile()
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func profileCreationFailurePropagates() async throws {
        let transport = PublishingTransport([missing, response(500, "{}")])
        await #expect(throws: StoryPublishingError.profileCreationFailed(500)) {
            try await StoryPublisher(repo: repo, transport: transport).ensureActorProfile()
        }
    }

    @Test(arguments: ["match", "image", "date", "uri", "malformed", "missing"]) func verifiesExistingRecordBeforeAcceptingRetry(variant: String) async throws {
        let record = try FlashesStoryRecordFactory.make(blob: variant == "image" ? ATProtoBlob(cid: "other", mimeType: "image/jpeg", size: photo.count) : blob, createdAt: variant == "date" ? date.addingTimeInterval(1) : date)
        let encoded = try JSONEncoder().encode(record)
        let json = "{\"uri\":\"\(variant == "uri" ? "at://other" : uri)\",\"cid\":\"existingcid\",\"value\":\(String(decoding: encoded, as: UTF8.self))}"
        let lookup = variant == "malformed" ? response(200, "{}") : variant == "missing" ? missing : response(200, json)
        let transport = PublishingTransport([try upload(), conflict, lookup])
        let publisher = StoryPublisher(repo: repo, transport: transport)
        if variant == "match" {
            #expect(try await publisher.publish(jpegData: photo, createdAt: date, recordKey: key) == PublishedStory(uri: uri, cid: "existingcid"))
        } else {
            await #expect(throws: StoryPublishingError.existingRecordMismatch) {
                try await publisher.publish(jpegData: photo, createdAt: date, recordKey: key)
            }
        }
        #expect(await transport.requests.count == 3)
    }

    @Test func rejectsOversizeBeforeNetwork() async throws {
        let transport = PublishingTransport([])
        let bytes = FlashesStoryContract.maximumImageBytes + 1
        await #expect(throws: StoryContractError.imageTooLarge(bytes)) {
            try await StoryPublisher(repo: repo, transport: transport).publish(jpegData: Data(repeating: 0, count: bytes), createdAt: date, recordKey: key)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: ["malformed", "mime", "size", "cid", "type", "failure"]) func rejectsInvalidUpload(variant: String) async throws {
        var json = "{\"blob\":{\"$type\":\"\(variant == "type" ? "other" : "blob")\",\"ref\":{\"$link\":\"\(variant == "cid" ? "" : "photo")\"},\"mimeType\":\"\(variant == "mime" ? "image/png" : "image/jpeg")\",\"size\":\(variant == "size" ? 4 : 3)}}"
        if variant == "malformed" { json = "{}" }
        let transport = PublishingTransport([response(variant == "failure" ? 503 : 200, json)])
        await #expect(throws: variant == "failure" ? StoryContractError.uploadFailed(503) : StoryContractError.invalidBlobResponse) {
            try await StoryPublisher(repo: repo, transport: transport).publish(jpegData: photo, createdAt: date, recordKey: key)
        }
    }

    @Test(arguments: ["malformed", "uri", "cid", "failure"]) func rejectsInvalidCreateResponse(variant: String) async throws {
        let json = variant == "malformed" ? "{}" : "{\"uri\":\"\(variant == "uri" ? "other" : uri)\",\"cid\":\"\(variant == "cid" ? "" : "record")\"}"
        let transport = PublishingTransport([try upload(), response(variant == "failure" ? 500 : 200, json)])
        await #expect(throws: variant == "failure" ? StoryContractError.createRecordFailed(500) : StoryContractError.invalidCreateRecordResponse) {
            try await StoryPublisher(repo: repo, transport: transport).publish(jpegData: photo, createdAt: date, recordKey: key)
        }
    }

    @Test func transportFailurePropagates() async throws {
        let transport = PublishingTransport([])
        await #expect(throws: PublishingTransport.StubError.self) {
            try await StoryPublisher(repo: repo, transport: transport).publish(jpegData: photo, createdAt: date, recordKey: key)
        }
    }

    @Test func storyContractWireShapeAndTimestampRemainStable() throws {
        let record = try FlashesStoryRecordFactory.make(blob: blob, createdAt: date)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        #expect(json["$type"] as? String == "blue.flashes.story.post")
        #expect(json["createdAt"] as? String == "2025-07-26T00:00:00.000Z")
        #expect(json["expiresInMinutes"] as? Int == 1440)
        let image = try #require(json["image"] as? [String: Any])
        #expect(image["$type"] as? String == "blob")
        #expect(image["mimeType"] as? String == "image/jpeg")
        #expect(image["size"] as? Int == photo.count)
        #expect(ATProtoTID.make(date: Date(timeIntervalSince1970: 0), clockIdentifier: 0) == "2222222222222")
        #expect(throws: StoryContractError.unsupportedMIMEType("image/png")) {
            try FlashesStoryRecordFactory.make(blob: ATProtoBlob(cid: "cid", mimeType: "image/png", size: 3), createdAt: date)
        }
    }

    @Test func scopeContractMatchesRequiredPermissions() {
        #expect(StoryPublisher.requiredOAuthScopes == ["atproto", "repo:blue.flashes.actor.profile?action=create", "repo:blue.flashes.story.post?action=create", "blob:image/jpeg"])
    }
}
