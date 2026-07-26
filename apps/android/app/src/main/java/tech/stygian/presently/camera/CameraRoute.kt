package tech.stygian.presently.camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import tech.stygian.presently.data.AppSettings
import tech.stygian.presently.data.LocalStoryDraft
import tech.stygian.presently.data.PresentlyDatabase
import tech.stygian.presently.data.SaveToPhotosPreference
import tech.stygian.presently.story.FlashesStoryContract
import java.io.File
import java.util.Locale

@Composable
fun CameraRoute() {
    val context = LocalContext.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasCameraPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    if (hasCameraPermission) {
        CameraScreen()
    } else {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(24.dp),
            ) {
                Text("Camera access is required to create a story.")
                Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                    Text("Allow camera")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CameraScreen() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val database = remember { PresentlyDatabase.get(context) }
    val dao = remember { database.presentlyDao() }
    val settingsFlow = remember(dao) {
        dao.observeSettings().map { it ?: AppSettings() }
    }
    val settings by settingsFlow.collectAsStateWithLifecycle(initialValue = AppSettings())
    val imageCapture = remember {
        ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .build()
    }
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var capturedJpeg by remember { mutableStateOf<ByteArray?>(null) }
    var saveThisPhoto by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var lensFacing by remember { mutableIntStateOf(CameraSelector.LENS_FACING_BACK) }
    var camera by remember { mutableStateOf<Camera?>(null) }
    var zoomRatio by remember { mutableFloatStateOf(1f) }
    var minimumZoomRatio by remember { mutableFloatStateOf(1f) }
    var maximumZoomRatio by remember { mutableFloatStateOf(1f) }
    var canSwitchCamera by remember { mutableStateOf(false) }

    fun setZoomRatio(requestedZoomRatio: Float) {
        val clampedZoomRatio = requestedZoomRatio.coerceIn(minimumZoomRatio, maximumZoomRatio)
        zoomRatio = clampedZoomRatio
        camera?.cameraControl?.setZoomRatio(clampedZoomRatio)
    }

    DisposableEffect(lifecycleOwner, lensFacing) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        var disposed = false
        val listener = Runnable {
            if (disposed) return@Runnable

            runCatching {
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val selector = CameraSelector.Builder()
                    .requireLensFacing(lensFacing)
                    .build()

                cameraProvider.unbindAll()
                camera = cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    selector,
                    preview,
                    imageCapture,
                )

                camera?.cameraInfo?.zoomState?.value?.let { zoomState ->
                    minimumZoomRatio = zoomState.minZoomRatio
                    maximumZoomRatio = zoomState.maxZoomRatio
                    zoomRatio = 1f.coerceIn(minimumZoomRatio, maximumZoomRatio)
                    camera?.cameraControl?.setZoomRatio(zoomRatio)
                }

                val otherFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
                    CameraSelector.LENS_FACING_FRONT
                } else {
                    CameraSelector.LENS_FACING_BACK
                }
                canSwitchCamera = cameraProvider.hasCamera(
                    CameraSelector.Builder()
                        .requireLensFacing(otherFacing)
                        .build(),
                )
            }.onFailure { error ->
                scope.launch {
                    snackbar.showSnackbar(
                        error.localizedMessage ?: "Could not open this camera.",
                    )
                }
            }
        }
        cameraProviderFuture.addListener(listener, ContextCompat.getMainExecutor(context))

        onDispose {
            disposed = true
            if (cameraProviderFuture.isDone) {
                cameraProviderFuture.get().unbindAll()
            }
        }
    }

    if (showSettings) {
        CameraSettingsSheet(
            selectedPreference = settings.preference,
            onPreferenceSelected = { preference ->
                scope.launch {
                    dao.upsertSettings(
                        settings.copy(saveToPhotosPreference = preference.name),
                    )
                }
            },
            onDismiss = { showSettings = false },
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        val jpeg = capturedJpeg
        if (jpeg == null) {
            AndroidView(
                factory = { previewView },
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(camera, minimumZoomRatio, maximumZoomRatio) {
                        detectTransformGestures { _, _, gestureZoom, _ ->
                            setZoomRatio(zoomRatio * gestureZoom)
                        }
                    },
            )
        } else {
            val bitmap = remember(jpeg) { BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) }
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "Captured story preview",
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxSize(),
            )
        }

        CameraTopBar(
            onSettings = { showSettings = true },
            modifier = Modifier.align(Alignment.TopCenter),
        )

        if (jpeg == null) {
            CameraControls(
                zoomRatio = zoomRatio,
                minimumZoomRatio = minimumZoomRatio,
                maximumZoomRatio = maximumZoomRatio,
                canSwitchCamera = canSwitchCamera,
                onZoomSelected = ::setZoomRatio,
                onCapture = {
                    saveThisPhoto = false
                    capturePhoto(
                        imageCapture = imageCapture,
                        context = context,
                        onCaptured = { capturedJpeg = it },
                        onError = { message -> scope.launch { snackbar.showSnackbar(message) } },
                    )
                },
                onSwitchCamera = {
                    lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
                        CameraSelector.LENS_FACING_FRONT
                    } else {
                        CameraSelector.LENS_FACING_BACK
                    }
                },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        } else {
            ReviewControls(
                preference = settings.preference,
                saveThisPhoto = saveThisPhoto,
                onSaveThisPhotoChanged = { saveThisPhoto = it },
                onRetake = {
                    saveThisPhoto = false
                    capturedJpeg = null
                },
                onPost = {
                    scope.launch {
                        if (jpeg.size > FlashesStoryContract.MaximumImageBytes) {
                            snackbar.showSnackbar("This image exceeds Flashes' 10 MiB limit.")
                            return@launch
                        }

                        val shouldSave = settings.preference.shouldSave(saveThisPhoto)
                        withContext(Dispatchers.IO) {
                            dao.insertDraft(LocalStoryDraft(imageData = jpeg))
                            if (shouldSave) {
                                PhotoLibrarySaver.save(context, jpeg)
                            }
                        }
                        saveThisPhoto = false
                        capturedJpeg = null
                        snackbar.showSnackbar(
                            if (shouldSave) {
                                "Pending story saved and copied to Photos."
                            } else {
                                "Pending story saved. OAuth publishing is the next slice."
                            },
                        )
                    }
                },
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }

        SnackbarHost(
            hostState = snackbar,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 72.dp),
        )
    }
}

@Composable
private fun CameraTopBar(
    onSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Presently",
            color = Color.White,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier
                .background(Color.Black.copy(alpha = 0.45f), CircleShape)
                .padding(horizontal = 14.dp, vertical = 9.dp),
        )
        Spacer(Modifier.weight(1f))
        IconButton(
            onClick = onSettings,
            modifier = Modifier.background(Color.Black.copy(alpha = 0.45f), CircleShape),
        ) {
            Icon(
                imageVector = Icons.Default.Settings,
                contentDescription = "Camera settings",
                tint = Color.White,
            )
        }
    }
}

@Composable
private fun CameraControls(
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

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            quickZoomRatios.forEach { quickZoomRatio ->
                TextButton(
                    onClick = { onZoomSelected(quickZoomRatio) },
                    modifier = Modifier.background(
                        Color.Black.copy(alpha = 0.5f),
                        CircleShape,
                    ),
                ) {
                    Text(
                        text = formatZoom(quickZoomRatio),
                        color = if (kotlin.math.abs(zoomRatio - quickZoomRatio) < 0.05f) {
                            Color(0xFFFFD54F)
                        } else {
                            Color.White
                        },
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Spacer(Modifier.size(56.dp))
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .size(82.dp)
                    .border(4.dp, Color.White, CircleShape)
                    .padding(7.dp)
                    .background(Color.White, CircleShape)
                    .clickable(onClick = onCapture)
                    .semantics { contentDescription = "Take photo" },
            )
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .background(Color.Black.copy(alpha = 0.5f), CircleShape)
                    .clickable(enabled = canSwitchCamera, onClick = onSwitchCamera)
                    .semantics { contentDescription = "Switch camera" },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "↻",
                    color = if (canSwitchCamera) Color.White else Color.Gray,
                    style = MaterialTheme.typography.headlineMedium,
                )
            }
        }
    }
}

@Composable
private fun ReviewControls(
    preference: SaveToPhotosPreference,
    saveThisPhoto: Boolean,
    onSaveThisPhotoChanged: (Boolean) -> Unit,
    onRetake: () -> Unit,
    onPost: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
        ),
        shape = RoundedCornerShape(24.dp),
        modifier = modifier
            .padding(16.dp)
            .fillMaxWidth(),
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(14.dp),
            modifier = Modifier.padding(18.dp),
        ) {
            when (preference) {
                SaveToPhotosPreference.ALWAYS -> {
                    Text("A copy will be saved to Photos")
                }
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
                Button(
                    onClick = onRetake,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Retake")
                }
                Button(
                    onClick = onPost,
                    modifier = Modifier.weight(1f),
                ) {
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
private fun CameraSettingsSheet(
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

private fun capturePhoto(
    imageCapture: ImageCapture,
    context: Context,
    onCaptured: (ByteArray) -> Unit,
    onError: (String) -> Unit,
) {
    val outputFile = File.createTempFile("presently-", ".jpg", context.cacheDir)
    val options = ImageCapture.OutputFileOptions.Builder(outputFile).build()

    imageCapture.takePicture(
        options,
        ContextCompat.getMainExecutor(context),
        object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                runCatching { outputFile.readBytes() }
                    .onSuccess(onCaptured)
                    .onFailure { onError(it.localizedMessage ?: "Could not read captured photo.") }
                outputFile.delete()
            }

            override fun onError(exception: ImageCaptureException) {
                outputFile.delete()
                onError(exception.localizedMessage ?: "Could not capture photo.")
            }
        },
    )
}
