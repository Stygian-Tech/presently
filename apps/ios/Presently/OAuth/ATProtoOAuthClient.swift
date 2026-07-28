import CryptoKit
import Foundation
import Security

actor ATProtoOAuthClient {
    private let store: OAuthSecureStore
    private let http: OAuthHTTPClient
    private let discovery: OAuthDiscovery

    init(
        store: OAuthSecureStore = OAuthSecureStore(),
        http: OAuthHTTPClient = OAuthHTTPClient()
    ) {
        self.store = store
        self.http = http
        discovery = OAuthDiscovery(http: http)
    }

    func prepareAuthorization(identifier: String) async throws -> URL {
        let clientMetadata: OAuthClientMetadata = try await http.getJSON(
            PresentlyOAuthConfiguration.clientID
        )
        guard PresentlyOAuthConfiguration
            .publishedMetadataSupportsRequiredScopes(clientMetadata.scope) else {
            throw OAuthValidationError.clientMetadataOutOfDate
        }

        let result = try await discovery.discover(identifier: identifier)
        let key = try DPoPKey(store: store)
        do {
            let state = randomToken()
            let verifier = randomToken(byteCount: 48)
            let challenge = Data(
                SHA256.hash(data: Data(verifier.utf8))
            ).base64URLEncodedString()

            let fields = [
                URLQueryItem(
                    name: "client_id",
                    value: PresentlyOAuthConfiguration.clientID.absoluteString
                ),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(
                    name: "redirect_uri",
                    value: PresentlyOAuthConfiguration.redirectURI.absoluteString
                ),
                URLQueryItem(
                    name: "scope",
                    value: PresentlyOAuthConfiguration.scope
                ),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "login_hint", value: result.inputIdentifier),
            ]
            let par = try await dpopFormRequest(
                url: result.server.pushedAuthorizationRequestEndpoint,
                fields: fields,
                key: key,
                nonce: nil
            )
            guard par.response.statusCode == 200 || par.response.statusCode == 201,
                  let object = try JSONSerialization.jsonObject(
                    with: par.response.data
                  ) as? [String: Any],
                  let requestURI = object["request_uri"] as? String,
                  !requestURI.isEmpty else {
                throw OAuthValidationError.unexpectedResponse(
                    par.response.statusCode
                )
            }

            let pending = PendingAuthorization(
                inputIdentifier: result.inputIdentifier,
                expectedDID: result.did,
                pdsURL: result.pdsURL,
                issuer: result.server.issuer,
                authorizationEndpoint: result.server.authorizationEndpoint,
                tokenEndpoint: result.server.tokenEndpoint,
                state: state,
                codeVerifier: verifier,
                dpopKeyID: key.id,
                authorizationServerNonce: par.nonce
            )
            try store.savePendingAuthorization(pending)

            var components = URLComponents(
                url: result.server.authorizationEndpoint,
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(
                    name: "client_id",
                    value: PresentlyOAuthConfiguration.clientID.absoluteString
                ),
                URLQueryItem(name: "request_uri", value: requestURI),
            ]
            guard let authorizationURL = components?.url else {
                throw OAuthValidationError.invalidAuthorizationServerMetadata
            }
            return authorizationURL
        } catch {
            try? store.deleteDPoPPrivateKey(id: key.id)
            throw error
        }
    }

    func completeAuthorization(callbackURL: URL) async throws -> OAuthSession {
        guard var pending = try store.loadPendingAuthorization() else {
            throw OAuthValidationError.invalidCallback
        }
        let callback = try validateCallback(callbackURL, pending: pending)
        let key = try DPoPKey(id: pending.dpopKeyID, store: store)
        let fields = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(
                name: "client_id",
                value: PresentlyOAuthConfiguration.clientID.absoluteString
            ),
            URLQueryItem(
                name: "redirect_uri",
                value: PresentlyOAuthConfiguration.redirectURI.absoluteString
            ),
            URLQueryItem(name: "code", value: callback.code),
            URLQueryItem(name: "code_verifier", value: pending.codeVerifier),
        ]
        let tokenResult = try await dpopFormRequest(
            url: pending.tokenEndpoint,
            fields: fields,
            key: key,
            nonce: pending.authorizationServerNonce
        )
        pending.authorizationServerNonce = tokenResult.nonce
        try store.savePendingAuthorization(pending)

        guard tokenResult.response.statusCode == 200,
              let token = try? JSONDecoder().decode(
                TokenResponse.self,
                from: tokenResult.response.data
              ),
              token.tokenType.caseInsensitiveCompare("DPoP") == .orderedSame,
              let refreshToken = token.refreshToken,
              !refreshToken.isEmpty else {
            throw OAuthValidationError.invalidTokenResponse
        }
        guard token.subject == pending.expectedDID else {
            throw OAuthValidationError.accountMismatch
        }
        let grantedScopes = token.scope.split(separator: " ").map(String.init)
        guard Set(PresentlyOAuthConfiguration.scopes)
            .isSubset(of: Set(grantedScopes)) else {
            throw OAuthValidationError.insufficientScope
        }

        try await discovery.validateAccount(
            token.subject,
            pdsURL: pending.pdsURL,
            issuer: pending.issuer
        )

        let session = OAuthSession(
            accountDID: token.subject,
            handle: pending.inputIdentifier.hasPrefix("did:")
                ? nil
                : pending.inputIdentifier,
            pdsURL: pending.pdsURL,
            issuer: pending.issuer,
            tokenEndpoint: pending.tokenEndpoint,
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            scopes: grantedScopes,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            dpopKeyID: pending.dpopKeyID,
            authorizationServerNonce: tokenResult.nonce,
            resourceServerNonce: nil,
            flashesActorProfileReady: nil
        )
        try store.saveSession(session)
        try store.deletePendingAuthorization()
        return try await ensureFlashesActorProfile(for: session)
    }

    func currentSession() throws -> OAuthSession? {
        try store.loadSession()
    }

    func validSession() async throws -> OAuthSession {
        guard let session = try store.loadSession() else {
            throw OAuthValidationError.sessionExpired
        }
        guard Set(PresentlyOAuthConfiguration.scopes)
            .isSubset(of: Set(session.scopes)) else {
            try? signOut()
            throw OAuthValidationError.insufficientScope
        }
        let activeSession = session.expiresAt.timeIntervalSinceNow > 30
            ? session
            : try await refresh(session)
        return try await ensureFlashesActorProfile(for: activeSession)
    }

    func signOut() throws {
        if let session = try store.loadSession() {
            try? store.deleteDPoPPrivateKey(id: session.dpopKeyID)
        }
        if let pending = try store.loadPendingAuthorization() {
            try? store.deleteDPoPPrivateKey(id: pending.dpopKeyID)
        }
        try store.deleteSession()
        try store.deletePendingAuthorization()
    }

    func publishStory(
        jpegData: Data,
        createdAt: Date,
        recordKey: String
    ) async throws -> PublishedStory {
        guard jpegData.count <= FlashesStoryContract.maximumImageBytes else {
            throw StoryContractError.imageTooLarge(jpegData.count)
        }

        var session = try await validSession()
        let uploadURL = try repoEndpoint(
            session.pdsURL,
            method: "com.atproto.repo.uploadBlob"
        )
        let uploadResult = try await dpopResourceRequest(
            url: uploadURL,
            body: jpegData,
            contentType: FlashesStoryContract.jpegMIMEType,
            session: session
        )
        session = uploadResult.session
        try store.saveSession(session)
        guard uploadResult.response.statusCode == 200 else {
            throw StoryContractError.uploadFailed(
                uploadResult.response.statusCode
            )
        }
        guard let uploaded = try? JSONDecoder().decode(
            UploadBlobResponse.self,
            from: uploadResult.response.data
        ), uploaded.blob.mimeType == FlashesStoryContract.jpegMIMEType,
           uploaded.blob.size == jpegData.count else {
            throw StoryContractError.invalidBlobResponse
        }

        let record = try FlashesStoryRecordFactory.make(
            blob: uploaded.blob,
            createdAt: createdAt
        )
        let createURL = try repoEndpoint(
            session.pdsURL,
            method: "com.atproto.repo.createRecord"
        )
        let createBody = try JSONEncoder().encode(
            CreateRecordRequest(
                repo: session.accountDID,
                collection: FlashesStoryContract.collection,
                recordKey: recordKey,
                record: record
            )
        )
        let createResult = try await dpopResourceJSONRequest(
            url: createURL,
            body: createBody,
            session: session
        )
        try store.saveSession(createResult.session)

        if Self.isRecordAlreadyExists(createResult.response) {
            return PublishedStory(
                uri: "at://\(session.accountDID)/\(FlashesStoryContract.collection)/\(recordKey)",
                cid: nil
            )
        }
        guard createResult.response.statusCode == 200 else {
            throw StoryContractError.createRecordFailed(
                createResult.response.statusCode
            )
        }
        guard let response = try? JSONDecoder().decode(
            CreateRecordResponse.self,
            from: createResult.response.data
        ), response.uri ==
            "at://\(session.accountDID)/\(FlashesStoryContract.collection)/\(recordKey)",
           !response.cid.isEmpty else {
            throw StoryContractError.invalidCreateRecordResponse
        }
        return PublishedStory(uri: response.uri, cid: response.cid)
    }

    private func refresh(_ session: OAuthSession) async throws -> OAuthSession {
        let key = try DPoPKey(id: session.dpopKeyID, store: store)
        let result = try await dpopFormRequest(
            url: session.tokenEndpoint,
            fields: [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(
                    name: "client_id",
                    value: PresentlyOAuthConfiguration.clientID.absoluteString
                ),
                URLQueryItem(name: "refresh_token", value: session.refreshToken),
            ],
            key: key,
            nonce: session.authorizationServerNonce
        )
        guard result.response.statusCode == 200,
              let token = try? JSONDecoder().decode(
                TokenResponse.self,
                from: result.response.data
              ),
              token.tokenType.caseInsensitiveCompare("DPoP") == .orderedSame,
              token.subject == session.accountDID,
              let refreshToken = token.refreshToken else {
            try? signOut()
            throw OAuthValidationError.sessionExpired
        }
        let scopes = token.scope.split(separator: " ").map(String.init)
        guard Set(PresentlyOAuthConfiguration.scopes).isSubset(of: Set(scopes)) else {
            try? signOut()
            throw OAuthValidationError.insufficientScope
        }
        let refreshed = OAuthSession(
            accountDID: session.accountDID,
            handle: session.handle,
            pdsURL: session.pdsURL,
            issuer: session.issuer,
            tokenEndpoint: session.tokenEndpoint,
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            scopes: scopes,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            dpopKeyID: session.dpopKeyID,
            authorizationServerNonce: result.nonce,
            resourceServerNonce: session.resourceServerNonce,
            flashesActorProfileReady: session.flashesActorProfileReady
        )
        try store.saveSession(refreshed)
        return refreshed
    }

    private func ensureFlashesActorProfile(
        for session: OAuthSession
    ) async throws -> OAuthSession {
        guard session.flashesActorProfileReady != true else {
            return session
        }

        let lookupURL = try repoEndpoint(
            session.pdsURL,
            method: "com.atproto.repo.getRecord",
            queryItems: [
                URLQueryItem(name: "repo", value: session.accountDID),
                URLQueryItem(
                    name: "collection",
                    value: FlashesActorProfileContract.collection
                ),
                URLQueryItem(
                    name: "rkey",
                    value: FlashesActorProfileContract.recordKey
                ),
            ]
        )
        let lookupResponse = try await http.get(
            lookupURL,
            headers: ["Accept": "application/json"]
        )

        if lookupResponse.statusCode == 200 {
            return try markFlashesActorProfileReady(session)
        }
        guard Self.isRecordNotFound(lookupResponse) else {
            throw OAuthValidationError.unexpectedResponse(
                lookupResponse.statusCode
            )
        }

        let createURL = try repoEndpoint(
            session.pdsURL,
            method: "com.atproto.repo.createRecord"
        )
        let body = try JSONEncoder().encode(
            CreateRecordRequest(
                repo: session.accountDID,
                collection: FlashesActorProfileContract.collection,
                recordKey: FlashesActorProfileContract.recordKey,
                record: FlashesActorProfileFactory.make(createdAt: Date())
            )
        )
        let result = try await dpopResourceJSONRequest(
            url: createURL,
            body: body,
            session: session
        )
        guard result.response.statusCode == 200
                || Self.isRecordAlreadyExists(result.response) else {
            throw OAuthValidationError.unexpectedResponse(
                result.response.statusCode
            )
        }

        var readySession = result.session
        readySession.flashesActorProfileReady = true
        try store.saveSession(readySession)
        return readySession
    }

    private func markFlashesActorProfileReady(
        _ session: OAuthSession
    ) throws -> OAuthSession {
        var readySession = session
        readySession.flashesActorProfileReady = true
        try store.saveSession(readySession)
        return readySession
    }

    private func dpopResourceJSONRequest(
        url: URL,
        body: Data,
        session: OAuthSession
    ) async throws -> (response: OAuthHTTPResponse, session: OAuthSession) {
        try await dpopResourceRequest(
            url: url,
            body: body,
            contentType: "application/json",
            session: session
        )
    }

    private func dpopResourceRequest(
        url: URL,
        body: Data,
        contentType: String,
        session: OAuthSession
    ) async throws -> (response: OAuthHTTPResponse, session: OAuthSession) {
        let key = try DPoPKey(id: session.dpopKeyID, store: store)
        var activeNonce = session.resourceServerNonce
        var updatedSession = session

        for attempt in 0..<2 {
            let proof = try key.proof(
                method: "POST",
                url: url,
                nonce: activeNonce,
                accessToken: session.accessToken
            )
            let response = try await http.post(
                url,
                body: body,
                contentType: contentType,
                headers: [
                    "Authorization": "DPoP \(session.accessToken)",
                    "DPoP": proof,
                ]
            )
            if let responseNonce = response.dpopNonce {
                activeNonce = responseNonce
                updatedSession.resourceServerNonce = responseNonce
            }
            if attempt == 0, responseRequiresDPoPNonce(response) {
                continue
            }
            return (response, updatedSession)
        }
        throw OAuthValidationError.dpopNonceMissing
    }

    private func repoEndpoint(
        _ pdsURL: URL,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let endpoint = pdsURL
            .appendingPathComponent("xrpc")
            .appendingPathComponent(method)
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw OAuthValidationError.invalidProtectedResourceMetadata
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw OAuthValidationError.invalidProtectedResourceMetadata
        }
        return url
    }

    static func isRecordNotFound(_ response: OAuthHTTPResponse) -> Bool {
        response.statusCode == 400
            && responseError(response) == "RecordNotFound"
    }

    static func isRecordAlreadyExists(_ response: OAuthHTTPResponse) -> Bool {
        response.statusCode == 400
            && responseError(response) == "RecordAlreadyExists"
    }

    private static func responseError(
        _ response: OAuthHTTPResponse
    ) -> String? {
        let object = try? JSONSerialization.jsonObject(
            with: response.data
        ) as? [String: Any]
        return object?["error"] as? String
    }

    private func dpopFormRequest(
        url: URL,
        fields: [URLQueryItem],
        key: DPoPKey,
        nonce: String?
    ) async throws -> (response: OAuthHTTPResponse, nonce: String) {
        var activeNonce = nonce
        for attempt in 0..<2 {
            let proof = try key.proof(
                method: "POST",
                url: url,
                nonce: activeNonce
            )
            let response = try await http.postForm(
                url,
                fields: fields,
                headers: ["DPoP": proof]
            )
            guard let responseNonce = response.dpopNonce else {
                throw OAuthValidationError.dpopNonceMissing
            }
            activeNonce = responseNonce
            if attempt == 0, responseRequiresDPoPNonce(response) {
                continue
            }
            return (response, responseNonce)
        }
        throw OAuthValidationError.dpopNonceMissing
    }

    private func responseRequiresDPoPNonce(_ response: OAuthHTTPResponse) -> Bool {
        guard response.statusCode == 400 || response.statusCode == 401,
              let object = try? JSONSerialization.jsonObject(
                with: response.data
              ) as? [String: Any] else {
            return false
        }
        return object["error"] as? String == "use_dpop_nonce"
    }

    private func validateCallback(
        _ url: URL,
        pending: PendingAuthorization
    ) throws -> (code: String, issuer: String) {
        guard url.scheme == PresentlyOAuthConfiguration.redirectURI.scheme,
              url.host == PresentlyOAuthConfiguration.redirectURI.host,
              url.path == PresentlyOAuthConfiguration.redirectURI.path,
              let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
              ) else {
            throw OAuthValidationError.invalidCallback
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard values[item.name] == nil else {
                throw OAuthValidationError.invalidCallback
            }
            values[item.name] = item.value ?? ""
        }
        guard values["state"] == pending.state else {
            throw OAuthValidationError.callbackStateMismatch
        }
        guard values["iss"] == pending.issuer.absoluteString else {
            throw OAuthValidationError.callbackIssuerMismatch
        }
        if let error = values["error"] {
            throw OAuthValidationError.authorizationDenied(
                values["error_description"] ?? error
            )
        }
        guard let code = values["code"], !code.isEmpty else {
            throw OAuthValidationError.invalidCallback
        }
        return (code, values["iss"]!)
    }

    private func randomToken(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}
