package tech.stygian.presently.oauth

object OAuthConfig {
    const val ClientId = "https://oauth.presently.photo/oauth/client-metadata.json"
    const val RedirectUri = "photo.presently.oauth:/oauth/callback"
    const val CallbackScheme = "photo.presently.oauth"

    val Scopes = listOf(
        "atproto",
        "repo:blue.flashes.actor.profile?action=create",
        "repo:blue.flashes.story.post?action=create",
        "blob:image/jpeg",
    )
    val Scope: String = Scopes.joinToString(" ")
}

class OAuthException(message: String) : Exception(message)
