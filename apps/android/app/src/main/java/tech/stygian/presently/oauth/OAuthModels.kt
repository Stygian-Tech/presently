package tech.stygian.presently.oauth

data class OAuthSession(
    val accountDid: String,
    val handle: String?,
    val pdsUrl: String,
    val issuer: String,
    val tokenEndpoint: String,
    val accessToken: String,
    val refreshToken: String,
    val scopes: List<String>,
    val expiresAtEpochMillis: Long,
    val dpopKeyId: String,
    val authorizationServerNonce: String?,
    val resourceServerNonce: String?,
    val flashesActorProfileReady: Boolean? = null,
) {
    val canPublishStory: Boolean
        get() = scopes.containsAll(OAuthConfig.Scopes) &&
            flashesActorProfileReady == true
}

data class PendingAuthorization(
    val inputIdentifier: String,
    val expectedDid: String,
    val pdsUrl: String,
    val issuer: String,
    val authorizationEndpoint: String,
    val tokenEndpoint: String,
    val state: String,
    val codeVerifier: String,
    val dpopKeyId: String,
    val authorizationServerNonce: String?,
)

data class AuthorizationServer(
    val issuer: String,
    val authorizationEndpoint: String,
    val tokenEndpoint: String,
    val parEndpoint: String,
)

data class DiscoveryResult(
    val inputIdentifier: String,
    val did: String,
    val handle: String?,
    val pdsUrl: String,
    val server: AuthorizationServer,
)
