package tech.stygian.presently.camera

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import tech.stygian.presently.data.SaveToPhotosPreference
import java.util.Locale

@Composable
internal fun CameraTopBar(
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(104.dp)
            .background(
                Brush.verticalGradient(
                    0f to Color.Black.copy(alpha = 0.58f),
                    1f to Color.Transparent,
                ),
            ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Presently",
                color = Color.White,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.weight(1f))
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.88f),
            ) {
                IconButton(onClick = onSettings) {
                    Icon(
                        imageVector = Icons.Default.Settings,
                        contentDescription = "Camera settings",
                        tint = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CameraControls(
    zoomRatio: Float,
    minimumZoomRatio: Float,
    maximumZoomRatio: Float,
    canSwitchCamera: Boolean,
    onZoomSelected: (Float) -> Unit,
    onCapture: () -> Unit,
    onSwitchCamera: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val quickZoomRatios = remember(minimumZoomRatio, maximumZoomRatio) {
        listOf(0.5f, 1f, 2f, 3f).filter {
            it >= minimumZoomRatio - 0.01f && it <= maximumZoomRatio + 0.01f
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(224.dp)
            .background(
                Brush.verticalGradient(
                    0f to Color.Transparent,
                    0.45f to Color.Black.copy(alpha = 0.18f),
                    1f to Color.Black.copy(alpha = 0.72f),
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.BottomCenter)
                .padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
            ) {
                SingleChoiceSegmentedButtonRow(
                    modifier = Modifier.padding(3.dp),
                ) {
                    quickZoomRatios.forEachIndexed { index, quickZoomRatio ->
                        SegmentedButton(
                            selected = kotlin.math.abs(
                                zoomRatio - quickZoomRatio,
                            ) < 0.05f,
                            onClick = { onZoomSelected(quickZoomRatio) },
                            shape = SegmentedButtonDefaults.itemShape(
                                index = index,
                                count = quickZoomRatios.size,
                            ),
                            colors = SegmentedButtonDefaults.colors(
                                activeContainerColor = MaterialTheme.colorScheme.primaryContainer,
                                activeContentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                                inactiveContainerColor = Color.Transparent,
                                inactiveContentColor = MaterialTheme.colorScheme.onSurface,
                                activeBorderColor = Color.Transparent,
                                inactiveBorderColor = Color.Transparent,
                            ),
                            icon = {},
                            label = {
                                Text(
                                    text = formatZoom(quickZoomRatio),
                                    fontWeight = FontWeight.SemiBold,
                                )
                            },
                            modifier = Modifier.size(width = 54.dp, height = 40.dp),
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(Modifier.size(52.dp))
                Spacer(Modifier.weight(1f))
                ShutterButton(onClick = onCapture)
                Spacer(Modifier.weight(1f))
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
                ) {
                    IconButton(
                        onClick = onSwitchCamera,
                        enabled = canSwitchCamera,
                        modifier = Modifier.size(52.dp),
                    ) {
                        CameraSwitchGlyph(
                            color = if (canSwitchCamera) {
                                MaterialTheme.colorScheme.onSurface
                            } else {
                                MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ShutterButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Canvas(
        modifier = modifier
            .size(78.dp)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "Take photo" },
    ) {
        val center = Offset(size.width / 2, size.height / 2)
        drawCircle(
            color = Color.White,
            radius = size.minDimension / 2 - 2.dp.toPx(),
            center = center,
            style = Stroke(width = 4.dp.toPx()),
        )
        drawCircle(
            color = Color.White,
            radius = size.minDimension / 2 - 10.dp.toPx(),
            center = center,
        )
    }
}

@Composable
private fun CameraSwitchGlyph(
    color: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier.size(24.dp)) {
        val strokeWidth = 2.25.dp.toPx()
        val inset = 4.dp.toPx()
        val arcSize = Size(size.width - inset * 2, size.height - inset * 2)
        val stroke = Stroke(width = strokeWidth, cap = StrokeCap.Round)

        drawArc(
            color = color,
            startAngle = 205f,
            sweepAngle = 205f,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = arcSize,
            style = stroke,
        )
        drawArc(
            color = color,
            startAngle = 25f,
            sweepAngle = 205f,
            useCenter = false,
            topLeft = Offset(inset, inset),
            size = arcSize,
            style = stroke,
        )

        val arrowSize = 3.5.dp.toPx()
        drawPath(
            path = Path().apply {
                moveTo(size.width - 2.5.dp.toPx(), 8.dp.toPx())
                lineTo(size.width - 2.5.dp.toPx() - arrowSize, 5.dp.toPx())
                lineTo(size.width - 2.5.dp.toPx() - arrowSize, 11.dp.toPx())
                close()
            },
            color = color,
        )
        drawPath(
            path = Path().apply {
                moveTo(2.5.dp.toPx(), 16.dp.toPx())
                lineTo(2.5.dp.toPx() + arrowSize, 13.dp.toPx())
                lineTo(2.5.dp.toPx() + arrowSize, 19.dp.toPx())
                close()
            },
            color = color,
        )
    }
}

@Composable
internal fun ReviewControls(
    preference: SaveToPhotosPreference,
    saveThisPhoto: Boolean,
    onSaveThisPhotoChanged: (Boolean) -> Unit,
    onRetake: () -> Unit,
    onPost: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        shape = MaterialTheme.shapes.large,
        modifier = modifier
            .padding(16.dp)
            .fillMaxWidth(),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.padding(18.dp),
        ) {
            when (preference) {
                SaveToPhotosPreference.ALWAYS -> Text("A copy will be saved to Photos")
                SaveToPhotosPreference.ASK -> {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Save this photo")
                        Spacer(Modifier.weight(1f))
                        Switch(
                            checked = saveThisPhoto,
                            onCheckedChange = onSaveThisPhotoChanged,
                        )
                    }
                }
                SaveToPhotosPreference.NEVER -> Unit
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Button(onClick = onRetake, modifier = Modifier.weight(1f)) {
                    Text("Retake")
                }
                Button(onClick = onPost, modifier = Modifier.weight(1f)) {
                    Text("Post story")
                }
            }
            Text(
                "Publishing remains gated until native OAuth and DPoP are wired.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CameraSettingsSheet(
    selectedPreference: SaveToPhotosPreference,
    onPreferenceSelected: (SaveToPhotosPreference) -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 24.dp, end = 24.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text("Camera settings", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Save captured photos",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 12.dp),
            )

            SaveToPhotosPreference.entries.forEach { preference ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onPreferenceSelected(preference) }
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selectedPreference == preference,
                        onClick = { onPreferenceSelected(preference) },
                    )
                    Column(modifier = Modifier.padding(start = 10.dp)) {
                        Text(preference.title)
                        Text(
                            preference.explanation,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

private val SaveToPhotosPreference.title: String
    get() = when (this) {
        SaveToPhotosPreference.ALWAYS -> "Always"
        SaveToPhotosPreference.ASK -> "Ask"
        SaveToPhotosPreference.NEVER -> "Never"
    }

private val SaveToPhotosPreference.explanation: String
    get() = when (this) {
        SaveToPhotosPreference.ALWAYS -> "Save every photo you post to your library."
        SaveToPhotosPreference.ASK -> "Show a Save to Photos option before each post."
        SaveToPhotosPreference.NEVER -> "Post without adding a copy to your library."
    }

private fun formatZoom(zoomRatio: Float): String =
    if (zoomRatio % 1f == 0f) {
        "${zoomRatio.toInt()}×"
    } else {
        String.format(Locale.US, "%.1f×", zoomRatio)
    }
