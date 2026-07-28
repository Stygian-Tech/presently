package tech.stygian.presently

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import tech.stygian.presently.camera.CameraRoute
import tech.stygian.presently.oauth.OAuthSessionManager
import tech.stygian.presently.ui.PresentlyTheme

class MainActivity : ComponentActivity() {
    private lateinit var auth: OAuthSessionManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        auth = OAuthSessionManager(applicationContext)
        enableEdgeToEdge()
        setContent {
            PresentlyTheme {
                CameraRoute(auth)
            }
        }
        lifecycleScope.launch {
            auth.handleCallback(intent?.data)
            auth.refreshIfNeeded()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        lifecycleScope.launch {
            auth.handleCallback(intent.data)
        }
    }
}
