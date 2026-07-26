package tech.stygian.presently.ui

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

private val PresentlyLightColors = lightColorScheme(
    primary = Color(0xFF315F9F),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD7E3FF),
    onPrimaryContainer = Color(0xFF001B3F),
    secondary = Color(0xFF555F71),
    secondaryContainer = Color(0xFFD9E3F8),
    tertiary = Color(0xFF705574),
    tertiaryContainer = Color(0xFFFAD8FC),
)

private val PresentlyDarkColors = darkColorScheme(
    primary = Color(0xFFA9C7FF),
    onPrimary = Color(0xFF003064),
    primaryContainer = Color(0xFF16477F),
    onPrimaryContainer = Color(0xFFD7E3FF),
    secondary = Color(0xFFBDC7DC),
    secondaryContainer = Color(0xFF3D4758),
    tertiary = Color(0xFFDDBCE0),
    tertiaryContainer = Color(0xFF573E5C),
)

private val PresentlyShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(20.dp),
    large = RoundedCornerShape(28.dp),
    extraLarge = RoundedCornerShape(32.dp),
)

@Composable
fun PresentlyTheme(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val darkTheme = isSystemInDarkTheme()
    val colorScheme = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && darkTheme ->
            dynamicDarkColorScheme(context)
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            dynamicLightColorScheme(context)
        darkTheme -> PresentlyDarkColors
        else -> PresentlyLightColors
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography(),
        shapes = PresentlyShapes,
        content = content,
    )
}
