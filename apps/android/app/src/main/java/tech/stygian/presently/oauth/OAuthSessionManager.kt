package tech.stygian.presently.oauth

import android.app.Activity
import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.time.Instant
import tech.stygian.presently.story.PublishedStory

data class OAuthUiState(
    val session: OAuthSession? = null,
    val isAuthorizing: Boolean = false,
    val errorMessage: String? = null,
)

class OAuthSessionManager(context: Context) {
    private val client = ATProtoOAuthClient(
        SecureOAuthStore(context.applicationContext),
    )
    private val mutableState = MutableStateFlow(
        OAuthUiState(session = client.currentSession()),
    )
    val state: StateFlow<OAuthUiState> = mutableState.asStateFlow()

    suspend fun signIn(activity: Activity, identifier: String) {
        mutableState.value = mutableState.value.copy(
            isAuthorizing = true,
            errorMessage = null,
        )
        runCatching {
            client.prepareAuthorization(identifier)
        }.onSuccess { url ->
            withContext(Dispatchers.Main) {
                CustomTabsIntent.Builder()
                    .setShowTitle(true)
                    .build()
                    .launchUrl(activity, Uri.parse(url))
            }
        }.onFailure(::fail)
    }

    suspend fun handleCallback(uri: Uri?) {
        if (uri?.scheme != OAuthConfig.CallbackScheme) return
        mutableState.value = mutableState.value.copy(
            isAuthorizing = true,
            errorMessage = null,
        )
        runCatching {
            client.completeAuthorization(uri.toString())
        }.onSuccess { session ->
            mutableState.value = OAuthUiState(session = session)
        }.onFailure(::fail)
    }

    suspend fun refreshIfNeeded() {
        if (mutableState.value.session == null) return
        runCatching { client.validSession() }
            .onSuccess { mutableState.value = OAuthUiState(session = it) }
            .onFailure(::fail)
    }

    fun signOut() {
        runCatching(client::signOut)
            .onSuccess { mutableState.value = OAuthUiState() }
            .onFailure(::fail)
    }

    suspend fun publishStory(
        jpegData: ByteArray,
        createdAt: Instant,
        recordKey: String,
    ): PublishedStory {
        val story = client.publishStory(jpegData, createdAt, recordKey)
        mutableState.value = OAuthUiState(session = client.currentSession())
        return story
    }

    fun cancelAuthorization() {
        client.cancelPendingAuthorization()
        mutableState.value = OAuthUiState(session = client.currentSession())
    }

    private fun fail(error: Throwable) {
        mutableState.value = OAuthUiState(
            session = client.currentSession(),
            isAuthorizing = false,
            errorMessage = userFacingMessage(error),
        )
    }

    private fun userFacingMessage(error: Throwable): String =
        if (error is OAuthException) {
            when {
                error.message?.startsWith("Presently’s login service") == true ->
                    error.message!!
                error.message?.startsWith("Presently couldn’t prepare") == true ->
                    error.message!!
                else ->
                    "We couldn’t connect that account. Check the username and try again."
            }
        } else {
            "We couldn’t connect that account. Check the username and try again."
        }
}
