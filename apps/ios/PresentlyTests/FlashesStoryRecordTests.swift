import CryptoKit
import Foundation
import Testing
@testable import Presently

struct FlashesStoryRecordTests {
    @Test
    func createsCurrentFlashesStoryShape() throws {
        let blob = ATProtoBlob(
            cid: "bafkreiexample",
            mimeType: "image/jpeg",
            size: 512_000
        )
        let date = Date(timeIntervalSince1970: 1_753_488_000)

        let record = try FlashesStoryRecordFactory.make(blob: blob, createdAt: date)
        let data = try JSONEncoder().encode(record)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["$type"] as? String == "blue.flashes.story.post")
        #expect(json["expiresInMinutes"] as? Int == 1_440)
        #expect(json["createdAt"] as? String == "2025-07-26T00:00:00.000Z")

        let image = try #require(json["image"] as? [String: Any])
        #expect(image["$type"] as? String == "blob")
        #expect(image["mimeType"] as? String == "image/jpeg")
        #expect(image["size"] as? Int == 512_000)
    }

    @Test
    func rejectsImagesOverPublishedLimit() {
        let blob = ATProtoBlob(
            cid: "bafkreiexample",
            mimeType: "image/jpeg",
            size: FlashesStoryContract.maximumImageBytes + 1
        )

        #expect(throws: StoryContractError.imageTooLarge(blob.size)) {
            try FlashesStoryRecordFactory.make(blob: blob, createdAt: Date())
        }
    }

    @Test
    func rejectsNonJPEGForMVP() {
        let blob = ATProtoBlob(
            cid: "bafkreiexample",
            mimeType: "image/png",
            size: 10
        )

        #expect(throws: StoryContractError.unsupportedMIMEType("image/png")) {
            try FlashesStoryRecordFactory.make(blob: blob, createdAt: Date())
        }
    }
}

struct CameraSessionQueueTests {
    @Test
    func performsCameraWorkOffTheMainThread() async throws {
        let queue = CameraSessionQueue(label: "tech.stygian.presently.camera-session.tests")

        let ranOnMainThread = try await queue.perform {
            Thread.isMainThread
        }

        #expect(!ranOnMainThread)
    }
}

struct SelfieFramingModeTests {
    @Test
    func exposesPortraitAndLandscapeControlsInStableOrder() {
        #expect(SelfieFramingMode.allCases == [.portrait, .landscape])
        #expect(SelfieFramingMode.portrait.title == "Portrait")
        #expect(SelfieFramingMode.landscape.title == "Landscape")
    }
}

struct SaveToPhotosPreferenceTests {
    @Test
    func alwaysSavesRegardlessOfPerPhotoChoice() {
        #expect(SaveToPhotosPreference.always.shouldSave(whenAsked: false))
        #expect(SaveToPhotosPreference.always.shouldSave(whenAsked: true))
    }

    @Test
    func askUsesThePerPhotoChoice() {
        #expect(!SaveToPhotosPreference.ask.shouldSave(whenAsked: false))
        #expect(SaveToPhotosPreference.ask.shouldSave(whenAsked: true))
    }

    @Test
    func neverSkipsSavingRegardlessOfPerPhotoChoice() {
        #expect(!SaveToPhotosPreference.never.shouldSave(whenAsked: false))
        #expect(!SaveToPhotosPreference.never.shouldSave(whenAsked: true))
    }

    @Test
    func legacyBooleanMigratesToAlwaysOrAsk() {
        let settings = AppSettings()
        settings.saveToPhotosPreferenceRawValue = nil

        settings.saveToPhotos = true
        #expect(settings.saveToPhotosPreference == .always)

        settings.saveToPhotos = false
        #expect(settings.saveToPhotosPreference == .ask)
    }
}

struct OAuthPermissionTests {
    @Test
    func acceptsStandardAndStructuredJSONMediaTypes() {
        #expect(OAuthHTTPClient.contentTypeIsJSON([
            "Content-Type": "application/json; charset=utf-8",
        ]))
        #expect(OAuthHTTPClient.contentTypeIsJSON([
            "content-type": "application/did+ld+json; charset=utf-8",
        ]))
        #expect(!OAuthHTTPClient.contentTypeIsJSON([
            "Content-Type": "text/html",
        ]))
    }

    @Test
    func requestsOnlyTheOperationsUsedByPresently() {
        #expect(PresentlyOAuthConfiguration.scopes == [
            "atproto",
            "repo:blue.flashes.actor.profile?action=create",
            "repo:blue.flashes.story.post?action=create",
            "blob:image/jpeg",
        ])
        #expect(
            PresentlyOAuthConfiguration.scope ==
                "atproto repo:blue.flashes.actor.profile?action=create repo:blue.flashes.story.post?action=create blob:image/jpeg"
        )
        #expect(!PresentlyOAuthConfiguration.scope.contains("transition:generic"))
        #expect(!PresentlyOAuthConfiguration.scope.contains("repo:*"))
        #expect(!PresentlyOAuthConfiguration.scope.contains("blob:*/*"))
    }

    @Test
    func detectsPublishedMetadataScopeDrift() {
        let oldScope =
            "atproto repo:blue.flashes.story.post?action=create blob:image/jpeg"

        #expect(
            !PresentlyOAuthConfiguration
                .publishedMetadataSupportsRequiredScopes(oldScope)
        )
        #expect(
            PresentlyOAuthConfiguration
                .publishedMetadataSupportsRequiredScopes(
                    PresentlyOAuthConfiguration.scope
                )
        )
        #expect(
            OAuthSessionManager.userFacingMessage(
                for: OAuthValidationError.clientMetadataOutOfDate
            ) == "Presently's sign-in service needs an update. Try again shortly."
        )
    }

    @Test
    func dpopProofUsesRequiredHeaderAndClaims() throws {
        let key = DPoPKey(
            id: "test-key",
            privateKey: P256.Signing.PrivateKey()
        )
        let proof = try key.proof(
            method: "POST",
            url: URL(string: "https://pds.example/xrpc/com.atproto.repo.uploadBlob")!,
            nonce: "server-nonce",
            accessToken: "access-token",
            now: Date(timeIntervalSince1970: 1_700_000_000),
            identifier: "unique-proof"
        )
        let segments = proof.split(separator: ".")
        #expect(segments.count == 3)
        let header = try #require(decodeJWTObject(String(segments[0])))
        let claims = try #require(decodeJWTObject(String(segments[1])))

        #expect(header["typ"] as? String == "dpop+jwt")
        #expect(header["alg"] as? String == "ES256")
        #expect((header["jwk"] as? [String: Any])?["crv"] as? String == "P-256")
        #expect(claims["htm"] as? String == "POST")
        #expect(claims["nonce"] as? String == "server-nonce")
        #expect(claims["jti"] as? String == "unique-proof")
        #expect(claims["ath"] as? String != nil)
    }

    private func decodeJWTObject(_ value: String) -> [String: Any]? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

struct FlashesActorProfileTests {
    @Test
    func createsTheDefaultSelfProfile() throws {
        let date = Date(timeIntervalSince1970: 1_753_488_000)
        let profile = FlashesActorProfileFactory.make(createdAt: date)
        let request = CreateRecordRequest(
            repo: "did:plc:example",
            collection: FlashesActorProfileContract.collection,
            recordKey: FlashesActorProfileContract.recordKey,
            record: profile
        )
        let data = try JSONEncoder().encode(request)
        let json = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let record = try #require(json["record"] as? [String: Any])

        #expect(json["repo"] as? String == "did:plc:example")
        #expect(json["collection"] as? String == "blue.flashes.actor.profile")
        #expect(json["rkey"] as? String == "self")
        #expect(record["$type"] as? String == "blue.flashes.actor.profile")
        #expect(record["createdAt"] as? String == "2025-07-26T00:00:00.000Z")
        #expect(record["showFeeds"] as? Bool == true)
        #expect(record["showLikes"] as? Bool == false)
        #expect(record["showLists"] as? Bool == true)
        #expect(record["showMedia"] as? Bool == true)
        #expect(record["mediaLayout"] as? String == "grid")
        #expect(record["enablePortfolio"] as? Bool == false)
        #expect(record["portfolioLayout"] as? String == "grid")
        #expect(record["allowRawDownload"] as? Bool == false)
    }

    @Test
    func treatsOnlyRecordNotFoundAsMissing() {
        let missing = OAuthHTTPResponse(
            data: Data(#"{"error":"RecordNotFound"}"#.utf8),
            statusCode: 400,
            headers: [:]
        )
        let serverFailure = OAuthHTTPResponse(
            data: Data(#"{"error":"InternalServerError"}"#.utf8),
            statusCode: 500,
            headers: [:]
        )

        #expect(ATProtoOAuthClient.isRecordNotFound(missing))
        #expect(!ATProtoOAuthClient.isRecordNotFound(serverFailure))
    }

    @Test
    func acceptsAnAlreadyExistsRaceAsSuccess() {
        let response = OAuthHTTPResponse(
            data: Data(#"{"error":"RecordAlreadyExists"}"#.utf8),
            statusCode: 400,
            headers: [:]
        )

        #expect(ATProtoOAuthClient.isRecordAlreadyExists(response))
    }

    @Test
    func publishingRequiresTheActorProfileToBeReady() {
        var session = OAuthSession(
            accountDID: "did:plc:example",
            handle: "example.test",
            pdsURL: URL(string: "https://pds.example")!,
            issuer: URL(string: "https://auth.example")!,
            tokenEndpoint: URL(string: "https://auth.example/token")!,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            scopes: PresentlyOAuthConfiguration.scopes,
            expiresAt: Date.distantFuture,
            dpopKeyID: "key",
            authorizationServerNonce: nil,
            resourceServerNonce: nil,
            flashesActorProfileReady: nil
        )

        #expect(!session.canPublishStory)
        session.flashesActorProfileReady = true
        #expect(session.canPublishStory)
    }
}

struct AccountSearchClientTests {
    @Test
    func buildsAnEncodedTypeaheadRequest() throws {
        let url = try AccountSearchClient.requestURL(
            for: "Jay @ Home",
            limit: 6
        )
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        #expect(url.path.hasSuffix("/app.bsky.actor.searchActorsTypeahead"))
        #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "Jay @ Home")
        #expect(components.queryItems?.first(where: { $0.name == "limit" })?.value == "6")
    }

    @Test
    func decodesFriendlyAccountSuggestions() throws {
        let data = Data(
            """
            {
              "actors": [{
                "did": "did:plc:example",
                "handle": "jay.example.com",
                "displayName": "Jay Example",
                "avatar": "https://cdn.example.com/avatar.jpg"
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(
            AccountSuggestionsResponse.self,
            from: data
        )
        let account = try #require(response.actors.first)

        #expect(account.did == "did:plc:example")
        #expect(account.handle == "jay.example.com")
        #expect(account.displayName == "Jay Example")
        #expect(account.avatar?.absoluteString == "https://cdn.example.com/avatar.jpg")
    }
}

struct CaptureIntentContextTests {
    @Test
    func preservesSelectedCameraAcrossSystemLaunches() throws {
        let context = PresentlyCaptureContext(facing: .front)
        let data = try JSONEncoder().encode(context)
        let restored = try JSONDecoder().decode(
            PresentlyCaptureContext.self,
            from: data
        )

        #expect(restored == context)
        #expect(restored.facing == .front)
    }
}
