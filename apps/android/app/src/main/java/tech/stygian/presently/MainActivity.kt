package tech.stygian.presently

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import tech.stygian.presently.camera.CameraRoute
import tech.stygian.presently.ui.PresentlyTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PresentlyTheme {
                CameraRoute()
            }
        }
    }
}
