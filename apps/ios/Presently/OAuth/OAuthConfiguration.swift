import Foundation

enum PresentlyOAuthConfiguration {
    static let clientID = URL(
        string: "https://oauth.presently.photo/oauth/client-metadata.json"
    )!
    static let redirectURI = URL(
        string: "photo.presently.oauth:/oauth/callback"
    )!
    static let callbackScheme = "photo.presently.oauth"

    static let scopes = [
        "atproto",
        "repo:blue.flashes.actor.profile?action=create",
        "repo:blue.flashes.story.post?action=create",
        "blob:image/jpeg",
    ]

    static var scope: String {
        scopes.joined(separator: " ")
    }

    static func publishedMetadataSupportsRequiredScopes(
        _ publishedScope: String
    ) -> Bool {
        Set(scopes).isSubset(
            of: Set(publishedScope.split(separator: " ").map(String.init))
        )
    }
}

enum OAuthValidationError: LocalizedError, Equatable {
    case invalidIdentifier
    case handleCouldNotBeResolved
    case invalidDIDDocument
    case missingPDS
    case invalidProtectedResourceMetadata
    case invalidAuthorizationServerMetadata
    case clientMetadataOutOfDate
    case invalidCallback
    case callbackStateMismatch
    case callbackIssuerMismatch
    case authorizationDenied(String)
    case invalidTokenResponse
    case accountMismatch
    case insufficientScope
    case dpopNonceMissing
    case sessionExpired
    case unexpectedResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            "Enter a valid AT Protocol handle or DID."
        case .handleCouldNotBeResolved:
            "That handle could not be resolved."
        case .invalidDIDDocument:
            "The account's DID document could not be verified."
        case .missingPDS:
            "The account does not declare an AT Protocol PDS."
        case .invalidProtectedResourceMetadata:
            "The PDS returned invalid OAuth resource metadata."
        case .invalidAuthorizationServerMetadata:
            "The authorization server does not meet the AT Protocol OAuth requirements."
        case .clientMetadataOutOfDate:
            "Presently's sign-in service needs an update. Try again shortly."
        case .invalidCallback:
            "The authorization callback was invalid."
        case .callbackStateMismatch:
            "The authorization callback did not match this sign-in attempt."
        case .callbackIssuerMismatch:
            "The authorization callback came from an unexpected server."
        case let .authorizationDenied(reason):
            "Authorization was not completed: \(reason)"
        case .invalidTokenResponse:
            "The authorization server returned an invalid token response."
        case .accountMismatch:
            "The authorized account did not match the account being connected."
        case .insufficientScope:
            "Presently was not granted permission to upload a JPEG and create a Flashes story."
        case .dpopNonceMissing:
            "The server did not return the DPoP nonce required by AT Protocol."
        case .sessionExpired:
            "Your Presently session has expired. Connect the account again."
        case let .unexpectedResponse(status):
            "The server returned HTTP \(status)."
        }
    }
}
