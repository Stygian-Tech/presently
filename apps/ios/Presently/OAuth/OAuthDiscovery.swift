import Foundation

struct OAuthDiscovery {
    struct Result: Sendable {
        let inputIdentifier: String
        let did: String
        let handle: String?
        let pdsURL: URL
        let server: AuthorizationServerMetadata
    }

    private let http: OAuthHTTPClient

    init(http: OAuthHTTPClient) {
        self.http = http
    }

    func discover(identifier rawIdentifier: String) async throws -> Result {
        var identifier = rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if identifier.hasPrefix("@") {
            identifier.removeFirst()
        }

        guard !identifier.isEmpty else {
            throw OAuthValidationError.invalidIdentifier
        }

        let handle: String?
        let did: String
        if identifier.hasPrefix("did:") {
            handle = nil
            did = identifier
        } else {
            guard isValidHandle(identifier) else {
                throw OAuthValidationError.invalidIdentifier
            }
            handle = identifier.lowercased()
            did = try await resolveHandle(handle!)
        }

        let didDocument = try await resolveDID(did)
        guard didDocument.id == did else {
            throw OAuthValidationError.invalidDIDDocument
        }
        if let handle {
            let claimedHandles = didDocument.alsoKnownAs ?? []
            guard claimedHandles.contains(where: {
                $0.caseInsensitiveCompare("at://\(handle)") == .orderedSame
            }) else {
                throw OAuthValidationError.invalidDIDDocument
            }
        }

        guard
            let service = didDocument.service?.first(where: {
                $0.id == "#atproto_pds" ||
                    $0.id == "\(did)#atproto_pds"
            }),
            service.type == "AtprotoPersonalDataServer",
            let pdsURL = secureOrigin(service.serviceEndpoint)
        else {
            throw OAuthValidationError.missingPDS
        }

        let resourceURL = pdsURL.appending(
            path: ".well-known/oauth-protected-resource",
            directoryHint: .notDirectory
        )
        let resource: ProtectedResourceMetadata = try await http.getJSON(
            resourceURL
        )
        guard
            resource.authorizationServers.count == 1,
            let issuer = secureOrigin(resource.authorizationServers[0])
        else {
            throw OAuthValidationError.invalidProtectedResourceMetadata
        }

        let metadataURL = issuer.appending(
            path: ".well-known/oauth-authorization-server",
            directoryHint: .notDirectory
        )
        let server: AuthorizationServerMetadata = try await http.getJSON(
            metadataURL
        )
        try validate(server: server, expectedIssuer: issuer)

        return Result(
            inputIdentifier: identifier,
            did: did,
            handle: handle,
            pdsURL: pdsURL,
            server: server
        )
    }

    func validateAccount(_ did: String, pdsURL: URL, issuer: URL) async throws {
        let document = try await resolveDID(did)
        guard
            document.id == did,
            let service = document.service?.first(where: {
                $0.id == "#atproto_pds" || $0.id == "\(did)#atproto_pds"
            }),
            secureOrigin(service.serviceEndpoint) == pdsURL
        else {
            throw OAuthValidationError.accountMismatch
        }

        let resource: ProtectedResourceMetadata = try await http.getJSON(
            pdsURL.appending(
                path: ".well-known/oauth-protected-resource",
                directoryHint: .notDirectory
            )
        )
        guard resource.authorizationServers.count == 1,
              secureOrigin(resource.authorizationServers[0]) == issuer else {
            throw OAuthValidationError.accountMismatch
        }
    }

    private func resolveHandle(_ handle: String) async throws -> String {
        if let url = URL(string: "https://\(handle)/.well-known/atproto-did"),
           let response = try? await http.get(url),
           response.statusCode == 200,
           let did = String(data: response.data, encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           did.hasPrefix("did:") {
            return did
        }

        var components = URLComponents(
            string: "https://cloudflare-dns.com/dns-query"
        )!
        components.queryItems = [
            URLQueryItem(name: "name", value: "_atproto.\(handle)"),
            URLQueryItem(name: "type", value: "TXT"),
        ]
        let response = try await http.get(
            components.url!,
            headers: ["Accept": "application/dns-json"]
        )
        guard response.statusCode == 200,
              let object = try JSONSerialization.jsonObject(
                with: response.data
              ) as? [String: Any],
              let answers = object["Answer"] as? [[String: Any]] else {
            throw OAuthValidationError.handleCouldNotBeResolved
        }
        for answer in answers {
            guard var value = answer["data"] as? String else { continue }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if value.hasPrefix("did=") {
                let did = String(value.dropFirst(4))
                if did.hasPrefix("did:") {
                    return did
                }
            }
        }
        throw OAuthValidationError.handleCouldNotBeResolved
    }

    private func resolveDID(_ did: String) async throws -> DIDDocument {
        let url: URL
        if did.hasPrefix("did:plc:") {
            guard let value = URL(string: "https://plc.directory/\(did)") else {
                throw OAuthValidationError.invalidDIDDocument
            }
            url = value
        } else if did.hasPrefix("did:web:") {
            let methodSpecificID = String(did.dropFirst("did:web:".count))
            let segments = methodSpecificID.split(separator: ":").map(String.init)
            guard let encodedHost = segments.first,
                  let host = encodedHost.removingPercentEncoding,
                  isValidWebDIDHost(host) else {
                throw OAuthValidationError.invalidDIDDocument
            }
            let path = segments.dropFirst().map {
                $0.removingPercentEncoding ?? $0
            }
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = path.isEmpty
                ? "/.well-known/did.json"
                : "/" + path.joined(separator: "/") + "/did.json"
            guard let value = components.url else {
                throw OAuthValidationError.invalidDIDDocument
            }
            url = value
        } else {
            throw OAuthValidationError.invalidDIDDocument
        }
        return try await http.getJSON(url)
    }

    private func validate(
        server: AuthorizationServerMetadata,
        expectedIssuer: URL
    ) throws {
        guard
            secureOrigin(server.issuer) == expectedIssuer,
            server.issuer == expectedIssuer,
            server.responseTypesSupported.contains("code"),
            server.grantTypesSupported.contains("authorization_code"),
            server.grantTypesSupported.contains("refresh_token"),
            server.codeChallengeMethodsSupported.contains("S256"),
            server.tokenEndpointAuthMethodsSupported.contains("none"),
            server.scopesSupported.contains("atproto"),
            server.authorizationResponseIssuerParameterSupported,
            server.requirePushedAuthorizationRequests,
            server.dpopSigningAlgorithmsSupported.contains("ES256"),
            server.clientIDMetadataDocumentSupported,
            isSecureEndpoint(server.authorizationEndpoint),
            isSecureEndpoint(server.tokenEndpoint),
            isSecureEndpoint(server.pushedAuthorizationRequestEndpoint)
        else {
            throw OAuthValidationError.invalidAuthorizationServerMetadata
        }
    }

    private func isValidHandle(_ value: String) -> Bool {
        value.count <= 253 &&
            value.range(
                of: #"(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$"#,
                options: .regularExpression
            ) != nil
    }

    private func isValidWebDIDHost(_ value: String) -> Bool {
        !value.isEmpty &&
            !value.contains("/") &&
            !value.contains("@") &&
            !value.contains("\\")
    }

    private func isSecureEndpoint(_ url: URL) -> Bool {
        url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    private func secureOrigin(_ value: String) -> URL? {
        guard let url = URL(string: value) else { return nil }
        return secureOrigin(url)
    }

    private func secureOrigin(_ url: URL) -> URL? {
        guard isSecureEndpoint(url) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = url.host
        components.port = url.port
        return components.url
    }
}
