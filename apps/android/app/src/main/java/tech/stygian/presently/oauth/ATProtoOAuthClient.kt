package tech.stygian.presently.oauth

import android.util.Base64
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import tech.stygian.presently.story.ATProtoBlob
import tech.stygian.presently.story.FlashesActorProfileContract
import tech.stygian.presently.story.FlashesActorProfileFactory
import tech.stygian.presently.story.FlashesStoryContract
import tech.stygian.presently.story.FlashesStoryRecordFactory
import tech.stygian.presently.story.PublishedStory
import tech.stygian.presently.story.StoryPublishingException
import tech.stygian.presently.story.toJson

class ATProtoOAuthClient(
    private val store: SecureOAuthStore,
    private val http: OAuthHttpClient = OAuthHttpClient(),
) {
    private val discovery = OAuthDiscovery(http)
    private val refreshMutex = Mutex()

    suspend fun prepareAuthorization(identifier: String): String {
        val publishedScope = http.getJson(OAuthConfig.ClientId).optString("scope")
            .split(" ")
            .filter(String::isNotBlank)
        if (!publishedScope.containsAll(OAuthConfig.Scopes)) {
            throw OAuthException(
                "Presently’s login service is being updated. Please try again shortly.",
            )
        }
        val result = discovery.discover(identifier)
        val key = DPoPKey.create()
        try {
            val state = randomToken()
            val verifier = randomToken(48)
            val challenge = MessageDigest.getInstance("SHA-256")
                .digest(verifier.toByteArray(Charsets.UTF_8))
                .base64Url()
            val fields = listOf(
                "client_id" to OAuthConfig.ClientId,
                "response_type" to "code",
                "redirect_uri" to OAuthConfig.RedirectUri,
                "scope" to OAuthConfig.Scope,
                "state" to state,
                "code_challenge" to challenge,
                "code_challenge_method" to "S256",
                "login_hint" to result.inputIdentifier,
            )
            val par = dpopFormRequest(result.server.parEndpoint, fields, key, null)
            if (par.first.statusCode !in listOf(200, 201)) {
                throw OAuthException("The authorization server rejected the request.")
            }
            val requestUri = JSONObject(String(par.first.body, Charsets.UTF_8))
                .optString("request_uri")
            if (requestUri.isEmpty()) {
                throw OAuthException("The authorization server returned an invalid PAR response.")
            }
            store.savePending(
                PendingAuthorization(
                    inputIdentifier = result.inputIdentifier,
                    expectedDid = result.did,
                    pdsUrl = result.pdsUrl,
                    issuer = result.server.issuer,
                    authorizationEndpoint = result.server.authorizationEndpoint,
                    tokenEndpoint = result.server.tokenEndpoint,
                    state = state,
                    codeVerifier = verifier,
                    dpopKeyId = key.id,
                    authorizationServerNonce = par.second,
                ),
            )
            return "${result.server.authorizationEndpoint}?" +
                "client_id=${OAuthConfig.ClientId.formEncode()}&" +
                "request_uri=${requestUri.formEncode()}"
        } catch (error: Throwable) {
            key.delete()
            throw error
        }
    }

    suspend fun completeAuthorization(callbackUrl: String): OAuthSession {
        val pending = store.loadPending()
            ?: throw OAuthException("There is no pending OAuth sign-in.")
        val callback = validateCallback(callbackUrl, pending)
        val key = DPoPKey.load(pending.dpopKeyId)
        val result = dpopFormRequest(
            pending.tokenEndpoint,
            listOf(
                "grant_type" to "authorization_code",
                "client_id" to OAuthConfig.ClientId,
                "redirect_uri" to OAuthConfig.RedirectUri,
                "code" to callback,
                "code_verifier" to pending.codeVerifier,
            ),
            key,
            pending.authorizationServerNonce,
        )
        if (result.first.statusCode != 200) {
            throw OAuthException("The authorization server rejected the token request.")
        }
        val token = JSONObject(String(result.first.body, Charsets.UTF_8))
        val subject = token.optString("sub")
        val scopes = token.optString("scope").split(" ").filter(String::isNotBlank)
        val refreshToken = token.optString("refresh_token")
        if (!token.optString("token_type").equals("DPoP", ignoreCase = true) ||
            subject != pending.expectedDid ||
            refreshToken.isEmpty() ||
            !scopes.containsAll(OAuthConfig.Scopes)
        ) {
            throw OAuthException(
                "The token response did not grant the account and permissions Presently requested.",
            )
        }
        discovery.validateAccount(subject, pending.pdsUrl, pending.issuer)
        val session = OAuthSession(
            accountDid = subject,
            handle = pending.inputIdentifier.takeUnless { it.startsWith("did:") },
            pdsUrl = pending.pdsUrl,
            issuer = pending.issuer,
            tokenEndpoint = pending.tokenEndpoint,
            accessToken = token.getString("access_token"),
            refreshToken = refreshToken,
            scopes = scopes,
            expiresAtEpochMillis = System.currentTimeMillis() +
                token.getLong("expires_in") * 1_000,
            dpopKeyId = pending.dpopKeyId,
            authorizationServerNonce = result.second,
            resourceServerNonce = null,
            flashesActorProfileReady = null,
        )
        store.saveSession(session)
        store.deletePending()
        return ensureFlashesActorProfile(session)
    }

    fun currentSession(): OAuthSession? = store.loadSession()

    suspend fun validSession(): OAuthSession = refreshMutex.withLock {
        val session = store.loadSession()
            ?: throw OAuthException("Connect an AT Protocol account.")
        if (!session.scopes.containsAll(OAuthConfig.Scopes)) {
            signOut()
            throw OAuthException("Your Presently session needs to be connected again.")
        }
        if (session.expiresAtEpochMillis - System.currentTimeMillis() > 30_000) {
            return@withLock ensureFlashesActorProfile(session)
        }
        ensureFlashesActorProfile(refresh(session))
    }

    suspend fun publishStory(
        jpegData: ByteArray,
        createdAt: Instant,
        recordKey: String,
    ): PublishedStory {
        if (jpegData.size > FlashesStoryContract.MaximumImageBytes) {
            throw StoryPublishingException("This photo is larger than Flashes’ 10 MiB limit.")
        }

        var session = validSession()
        val upload = dpopResourceRequest(
            url = repoEndpoint(session.pdsUrl, "com.atproto.repo.uploadBlob"),
            body = jpegData,
            contentType = FlashesStoryContract.JpegMimeType,
            session = session,
        )
        session = upload.second
        store.saveSession(session)
        if (upload.first.statusCode != 200) {
            throw StoryPublishingException("The photo upload failed. Please try again.")
        }
        val blobObject = runCatching {
            JSONObject(String(upload.first.body, Charsets.UTF_8)).getJSONObject("blob")
        }.getOrElse {
            throw StoryPublishingException("The photo server returned an invalid upload.")
        }
        val reference = blobObject.optJSONObject("ref")
        val blob = ATProtoBlob(
            type = blobObject.optString("\$type", "blob"),
            cid = reference?.optString("\$link").orEmpty(),
            mimeType = blobObject.optString("mimeType"),
            size = blobObject.optInt("size", -1),
        )
        if (blob.cid.isBlank() ||
            blob.mimeType != FlashesStoryContract.JpegMimeType ||
            blob.size != jpegData.size
        ) {
            throw StoryPublishingException("The photo server returned an invalid upload.")
        }

        val record = FlashesStoryRecordFactory.create(blob, createdAt)
        val createBody = JSONObject().apply {
            put("repo", session.accountDid)
            put("collection", FlashesStoryContract.Collection)
            put("rkey", recordKey)
            put("record", record.toJson())
        }.toString().toByteArray(Charsets.UTF_8)
        val create = dpopResourceRequest(
            url = repoEndpoint(session.pdsUrl, "com.atproto.repo.createRecord"),
            body = createBody,
            contentType = "application/json",
            session = session,
        )
        store.saveSession(create.second)
        val expectedUri =
            "at://${session.accountDid}/${FlashesStoryContract.Collection}/$recordKey"
        if (isError(create.first, "RecordAlreadyExists")) {
            return PublishedStory(expectedUri, null)
        }
        if (create.first.statusCode != 200) {
            throw StoryPublishingException("The story could not be posted. Please try again.")
        }
        val response = runCatching {
            JSONObject(String(create.first.body, Charsets.UTF_8))
        }.getOrElse {
            throw StoryPublishingException("The photo server returned an invalid story.")
        }
        val uri = response.optString("uri")
        val cid = response.optString("cid")
        if (uri != expectedUri || cid.isBlank()) {
            throw StoryPublishingException("The photo server returned an invalid story.")
        }
        return PublishedStory(uri, cid)
    }

    fun signOut() {
        store.loadSession()?.let { runCatching { DPoPKey.load(it.dpopKeyId).delete() } }
        store.loadPending()?.let { runCatching { DPoPKey.load(it.dpopKeyId).delete() } }
        store.deleteSession()
        store.deletePending()
    }

    fun cancelPendingAuthorization() {
        store.loadPending()?.let {
            runCatching { DPoPKey.load(it.dpopKeyId).delete() }
        }
        store.deletePending()
    }

    private suspend fun refresh(session: OAuthSession): OAuthSession {
        val key = DPoPKey.load(session.dpopKeyId)
        val result = dpopFormRequest(
            session.tokenEndpoint,
            listOf(
                "grant_type" to "refresh_token",
                "client_id" to OAuthConfig.ClientId,
                "refresh_token" to session.refreshToken,
            ),
            key,
            session.authorizationServerNonce,
        )
        if (result.first.statusCode != 200) {
            signOut()
            throw OAuthException("Your Presently session expired. Connect it again.")
        }
        val token = JSONObject(String(result.first.body, Charsets.UTF_8))
        val scopes = token.optString("scope").split(" ").filter(String::isNotBlank)
        if (!token.optString("token_type").equals("DPoP", ignoreCase = true) ||
            token.optString("sub") != session.accountDid ||
            !scopes.containsAll(OAuthConfig.Scopes) ||
            token.optString("refresh_token").isEmpty()
        ) {
            signOut()
            throw OAuthException("Your Presently session is no longer valid.")
        }
        val refreshed = session.copy(
            accessToken = token.getString("access_token"),
            refreshToken = token.getString("refresh_token"),
            scopes = scopes,
            expiresAtEpochMillis = System.currentTimeMillis() +
                token.getLong("expires_in") * 1_000,
            authorizationServerNonce = result.second,
        )
        store.saveSession(refreshed)
        return refreshed
    }

    private suspend fun ensureFlashesActorProfile(session: OAuthSession): OAuthSession {
        if (session.flashesActorProfileReady == true) return session
        val lookupUrl = repoEndpoint(
            session.pdsUrl,
            "com.atproto.repo.getRecord",
            listOf(
                "repo" to session.accountDid,
                "collection" to FlashesActorProfileContract.Collection,
                "rkey" to FlashesActorProfileContract.RecordKey,
            ),
        )
        val lookup = http.get(lookupUrl, mapOf("Accept" to "application/json"))
        if (lookup.statusCode == 200) {
            return session.copy(flashesActorProfileReady = true).also(store::saveSession)
        }
        if (!isError(lookup, "RecordNotFound")) {
            throw OAuthException("Presently couldn’t prepare this account for stories.")
        }

        val body = JSONObject().apply {
            put("repo", session.accountDid)
            put("collection", FlashesActorProfileContract.Collection)
            put("rkey", FlashesActorProfileContract.RecordKey)
            put("record", FlashesActorProfileFactory.create(Instant.now()))
        }.toString().toByteArray(Charsets.UTF_8)
        val create = dpopResourceRequest(
            repoEndpoint(session.pdsUrl, "com.atproto.repo.createRecord"),
            body,
            "application/json",
            session,
        )
        if (create.first.statusCode != 200 &&
            !isError(create.first, "RecordAlreadyExists")
        ) {
            throw OAuthException("Presently couldn’t prepare this account for stories.")
        }
        return create.second.copy(flashesActorProfileReady = true).also(store::saveSession)
    }

    private suspend fun dpopResourceRequest(
        url: String,
        body: ByteArray,
        contentType: String,
        session: OAuthSession,
    ): Pair<OAuthHttpResponse, OAuthSession> {
        val key = DPoPKey.load(session.dpopKeyId)
        var nonce = session.resourceServerNonce
        var updatedSession = session
        repeat(2) { attempt ->
            val response = http.post(
                url,
                body,
                contentType,
                mapOf(
                    "Authorization" to "DPoP ${session.accessToken}",
                    "DPoP" to key.proof(
                        method = "POST",
                        url = url,
                        nonce = nonce,
                        accessToken = session.accessToken,
                    ),
                ),
            )
            response.dpopNonce?.let {
                nonce = it
                updatedSession = updatedSession.copy(resourceServerNonce = it)
            }
            if (attempt == 0 && response.statusCode in listOf(400, 401) &&
                isError(response, "use_dpop_nonce")
            ) {
                return@repeat
            }
            return response to updatedSession
        }
        throw OAuthException("The photo server did not accept its security nonce.")
    }

    private fun repoEndpoint(
        pdsUrl: String,
        method: String,
        queryItems: List<Pair<String, String>> = emptyList(),
    ): String {
        val base = "${pdsUrl.trimEnd('/')}/xrpc/$method"
        if (queryItems.isEmpty()) return base
        return "$base?" + queryItems.joinToString("&") { (name, value) ->
            "${name.formEncode()}=${value.formEncode()}"
        }
    }

    private fun isError(response: OAuthHttpResponse, expected: String): Boolean =
        runCatching {
            JSONObject(String(response.body, Charsets.UTF_8)).optString("error") == expected
        }.getOrDefault(false)

    private suspend fun dpopFormRequest(
        url: String,
        fields: List<Pair<String, String>>,
        key: DPoPKey,
        startingNonce: String?,
    ): Pair<OAuthHttpResponse, String> {
        var nonce = startingNonce
        repeat(2) { attempt ->
            val response = http.postForm(
                url,
                fields,
                mapOf("DPoP" to key.proof("POST", url, nonce)),
            )
            val responseNonce = response.dpopNonce
                ?: throw OAuthException("The server omitted its required DPoP nonce.")
            nonce = responseNonce
            val error = runCatching {
                JSONObject(String(response.body, Charsets.UTF_8)).optString("error")
            }.getOrNull()
            if (attempt == 0 && response.statusCode in listOf(400, 401) &&
                error == "use_dpop_nonce"
            ) {
                return@repeat
            }
            return response to responseNonce
        }
        throw OAuthException("The server did not accept its DPoP nonce.")
    }

    private fun validateCallback(url: String, pending: PendingAuthorization): String {
        val uri = URI(url)
        val expected = URI(OAuthConfig.RedirectUri)
        if (uri.scheme != expected.scheme || uri.host != expected.host ||
            uri.path != expected.path
        ) {
            throw OAuthException("The OAuth callback URI was invalid.")
        }
        val values = mutableMapOf<String, String>()
        uri.rawQuery.orEmpty().split("&")
            .filter(String::isNotEmpty)
            .forEach {
                val parts = it.split("=", limit = 2)
                val name = parts[0].formDecode()
                if (values.containsKey(name)) {
                    throw OAuthException("The OAuth callback included duplicate parameters.")
                }
                values[name] = parts.getOrElse(1) { "" }.formDecode()
            }
        if (values["state"] != pending.state) {
            throw OAuthException("The OAuth callback state did not match.")
        }
        if (values["iss"] != pending.issuer) {
            throw OAuthException("The OAuth callback came from an unexpected server.")
        }
        values["error"]?.let {
            throw OAuthException(values["error_description"] ?: it)
        }
        return values["code"]?.takeIf(String::isNotEmpty)
            ?: throw OAuthException("The OAuth callback did not include a code.")
    }

    private fun randomToken(size: Int = 32): String =
        ByteArray(size).also(SecureRandom()::nextBytes).base64Url()

    private fun ByteArray.base64Url(): String = Base64.encodeToString(
        this,
        Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
    )

    private fun String.formEncode() = URLEncoder.encode(this, Charsets.UTF_8.name())
    private fun String.formDecode() = URLDecoder.decode(this, Charsets.UTF_8.name())
}
