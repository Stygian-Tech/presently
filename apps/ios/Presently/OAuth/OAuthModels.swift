import Foundation

struct OAuthSession: Codable, Equatable, Sendable {
    let accountDID: String
    let handle: String?
    let pdsURL: URL
    let issuer: URL
    let tokenEndpoint: URL
    let accessToken: String
    let refreshToken: String
    let scopes: [String]
    let expiresAt: Date
    let dpopKeyID: String
    var authorizationServerNonce: String?
    var resourceServerNonce: String?
    var flashesActorProfileReady: Bool?

    var canPublishStory: Bool {
        flashesActorProfileReady == true
            && Set(PresentlyOAuthConfiguration.scopes).isSubset(of: Set(scopes))
    }
}

struct PendingAuthorization: Codable, Equatable, Sendable {
    let inputIdentifier: String
    let expectedDID: String
    let pdsURL: URL
    let issuer: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let state: String
    let codeVerifier: String
    let dpopKeyID: String
    var authorizationServerNonce: String?
}

struct DIDDocument: Decodable {
    struct Service: Decodable {
        let id: String
        let type: String
        let serviceEndpoint: String
    }

    let id: String
    let alsoKnownAs: [String]?
    let service: [Service]?
}

struct ProtectedResourceMetadata: Decodable {
    let authorizationServers: [URL]

    enum CodingKeys: String, CodingKey {
        case authorizationServers = "authorization_servers"
    }
}

struct OAuthClientMetadata: Decodable {
    let scope: String
}

struct AuthorizationServerMetadata: Decodable {
    let issuer: URL
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let pushedAuthorizationRequestEndpoint: URL
    let responseTypesSupported: [String]
    let grantTypesSupported: [String]
    let codeChallengeMethodsSupported: [String]
    let tokenEndpointAuthMethodsSupported: [String]
    let scopesSupported: [String]
    let authorizationResponseIssuerParameterSupported: Bool
    let requirePushedAuthorizationRequests: Bool
    let dpopSigningAlgorithmsSupported: [String]
    let clientIDMetadataDocumentSupported: Bool

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case pushedAuthorizationRequestEndpoint = "pushed_authorization_request_endpoint"
        case responseTypesSupported = "response_types_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        case scopesSupported = "scopes_supported"
        case authorizationResponseIssuerParameterSupported =
            "authorization_response_iss_parameter_supported"
        case requirePushedAuthorizationRequests = "require_pushed_authorization_requests"
        case dpopSigningAlgorithmsSupported = "dpop_signing_alg_values_supported"
        case clientIDMetadataDocumentSupported =
            "client_id_metadata_document_supported"
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let refreshToken: String?
    let expiresIn: Int
    let scope: String
    let subject: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case subject = "sub"
    }
}
