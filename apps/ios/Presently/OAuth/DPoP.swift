import CryptoKit
import Foundation

struct DPoPKey: Sendable {
    let id: String
    private let privateKey: P256.Signing.PrivateKey

    init(store: OAuthSecureStore) throws {
        id = UUID().uuidString
        privateKey = P256.Signing.PrivateKey()
        try store.saveDPoPPrivateKey(privateKey.rawRepresentation, id: id)
    }

    init(id: String, store: OAuthSecureStore) throws {
        guard let data = try store.loadDPoPPrivateKey(id: id) else {
            throw OAuthValidationError.sessionExpired
        }
        self.id = id
        privateKey = try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    init(id: String, privateKey: P256.Signing.PrivateKey) {
        self.id = id
        self.privateKey = privateKey
    }

    func proof(
        method: String,
        url: URL,
        nonce: String?,
        accessToken: String? = nil,
        now: Date = Date(),
        identifier: String = UUID().uuidString
    ) throws -> String {
        let publicKey = privateKey.publicKey.x963Representation
        guard publicKey.count == 65 else {
            throw OAuthValidationError.invalidTokenResponse
        }

        let header: [String: Any] = [
            "typ": "dpop+jwt",
            "alg": "ES256",
            "jwk": [
                "kty": "EC",
                "crv": "P-256",
                "x": Data(publicKey[1...32]).base64URLEncodedString(),
                "y": Data(publicKey[33...64]).base64URLEncodedString(),
            ],
        ]

        var claims: [String: Any] = [
            "jti": identifier,
            "htm": method.uppercased(),
            "htu": normalizedHTU(url).absoluteString,
            "iat": Int(now.timeIntervalSince1970),
        ]
        if let nonce {
            claims["nonce"] = nonce
        }
        if let accessToken {
            claims["ath"] = Data(
                SHA256.hash(data: Data(accessToken.utf8))
            ).base64URLEncodedString()
        }

        let encodedHeader = try JSONSerialization.data(withJSONObject: header)
            .base64URLEncodedString()
        let encodedClaims = try JSONSerialization.data(withJSONObject: claims)
            .base64URLEncodedString()
        let signingInput = "\(encodedHeader).\(encodedClaims)"
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        return "\(signingInput).\(signature.rawRepresentation.base64URLEncodedString())"
    }

    private func normalizedHTU(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
