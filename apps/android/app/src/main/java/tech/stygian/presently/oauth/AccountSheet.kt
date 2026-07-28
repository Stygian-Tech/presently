package tech.stygian.presently.oauth

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountSheet(
    auth: OAuthSessionManager,
    onDismiss: () -> Unit,
) {
    val activity = checkNotNull(LocalActivity.current)
    val state by auth.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val searchClient = remember { AccountSearchClient() }
    var identifier by remember { mutableStateOf("") }
    var suggestions by remember { mutableStateOf(emptyList<AccountSuggestion>()) }
    var isSearching by remember { mutableStateOf(false) }

    fun connect(value: String = identifier) {
        val normalized = value.trim().removePrefix("@")
        if (normalized.isNotEmpty()) {
            suggestions = emptyList()
            scope.launch { auth.signIn(activity, normalized) }
        }
    }

    LaunchedEffect(identifier) {
        val query = identifier.trim()
        suggestions = emptyList()
        if (query.removePrefix("@").length < 2 || state.isAuthorizing) return@LaunchedEffect
        delay(250)
        isSearching = true
        suggestions = runCatching { searchClient.search(query) }.getOrDefault(emptyList())
        isSearching = false
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 24.dp, end = 24.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                "Logging Into the Atmosphere",
                style = MaterialTheme.typography.headlineSmall,
            )

            val session = state.session
            if (session != null) {
                Text(
                    if (session.canPublishStory) {
                        "You’re Connected"
                    } else {
                        "Finish Account Setup"
                    },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "@${session.handle ?: session.accountDid}",
                    style = MaterialTheme.typography.bodyLarge,
                )
                Text(
                    if (session.canPublishStory) {
                        "Presently is ready to post your stories."
                    } else {
                        "Presently still needs to prepare this account for Flashes stories."
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (!session.canPublishStory) {
                    Button(
                        onClick = { scope.launch { auth.refreshIfNeeded() } },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Try Again")
                    }
                }
                state.errorMessage?.let {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
                OutlinedButton(
                    onClick = auth::signOut,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Log Out")
                }
            } else {
                Text(
                    "Enter your Bluesky username. Your provider will open securely to finish logging in.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = identifier,
                    onValueChange = { identifier = it },
                    label = { Text("Username") },
                    placeholder = { Text("@you.bsky.social") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { connect() }),
                    enabled = !state.isAuthorizing,
                    modifier = Modifier.fillMaxWidth(),
                )

                if (isSearching) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
                suggestions.forEach { suggestion ->
                    AccountSuggestionRow(
                        suggestion = suggestion,
                        onClick = {
                            identifier = suggestion.handle
                            connect(suggestion.handle)
                        },
                    )
                }

                Button(
                    onClick = { connect() },
                    enabled = identifier.isNotBlank() && !state.isAuthorizing,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Continue")
                }
                if (state.isAuthorizing) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    OutlinedButton(
                        onClick = auth::cancelAuthorization,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Cancel")
                    }
                }
                state.errorMessage?.let {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
                Text(
                    "Presently only asks to upload photos and create your Flashes profile and stories.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun AccountSuggestionRow(
    suggestion: AccountSuggestion,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (suggestion.avatarUrl != null) {
            AsyncImage(
                model = suggestion.avatarUrl,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(44.dp)
                    .clip(CircleShape),
            )
        } else {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.secondaryContainer,
                modifier = Modifier.size(44.dp),
            ) {
                Text(
                    text = suggestion.handle.first().uppercase(),
                    modifier = Modifier.padding(13.dp),
                )
            }
        }
        Column {
            suggestion.displayName?.let {
                Text(it, fontWeight = FontWeight.SemiBold)
            }
            Text(
                "@${suggestion.handle}",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        Spacer(Modifier.weight(1f))
    }
}
