package tech.stygian.presently.camera

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
import tech.stygian.presently.story.FlashesStoryContract
import java.io.File

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

@Composable
private fun CameraScreen() {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val database = remember { PresentlyDatabase.get(context) }
    val dao = remember { database.presentlyDao() }
    val settingsFlow = remember(dao) {
        dao.observeSettings().map { it?.saveToPhotos ?: false }
    }
    val saveToPhotos by settingsFlow
        .collectAsStateWithLifecycle(initialValue = false)
    val imageCapture = remember { ImageCapture.Builder().build() }
    val previewView = remember { PreviewView(context) }
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    var capturedJpeg by remember { mutableStateOf<ByteArray?>(null) }

    DisposableEffect(lifecycleOwner) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        val listener = Runnable {
            val cameraProvider = cameraProviderFuture.get()
            val preview = Preview.Builder().build().also {
                it.surfaceProvider = previewView.surfaceProvider
            }
            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(
                lifecycleOwner,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                imageCapture,
            )
        }
        cameraProviderFuture.addListener(listener, ContextCompat.getMainExecutor(context))

        onDispose {
            if (cameraProviderFuture.isDone) {
                cameraProviderFuture.get().unbindAll()
            }
        }
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
                modifier = Modifier.fillMaxSize(),
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

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .align(Alignment.TopCenter)
                .padding(18.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("Presently", style = MaterialTheme.typography.titleLarge)
            Text("OAuth next", style = MaterialTheme.typography.labelMedium)
        }

        if (jpeg == null) {
            Button(
                onClick = {
                    capturePhoto(
                        imageCapture = imageCapture,
                        context = context,
                        onCaptured = { capturedJpeg = it },
                        onError = { message -> scope.launch { snackbar.showSnackbar(message) } },
                    )
                },
                shape = CircleShape,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 32.dp)
                    .size(82.dp)
                    .semantics { contentDescription = "Take photo" },
            ) {}
        } else {
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
                ),
                shape = RoundedCornerShape(22.dp),
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(16.dp)
                    .fillMaxWidth(),
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.padding(16.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("Save to Photos")
                        Spacer(Modifier.weight(1f))
                        Switch(
                            checked = saveToPhotos,
                            onCheckedChange = { enabled ->
                                scope.launch {
                                    dao.upsertSettings(AppSettings(saveToPhotos = enabled))
                                }
                            },
                        )
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Button(
                            onClick = { capturedJpeg = null },
                            modifier = Modifier.weight(1f),
                        ) {
                            Text("Retake")
                        }
                        Button(
                            onClick = {
                                scope.launch {
                                    if (jpeg.size > FlashesStoryContract.MaximumImageBytes) {
                                        snackbar.showSnackbar("This image exceeds Flashes' 10 MiB limit.")
                                        return@launch
                                    }
                                    withContext(Dispatchers.IO) {
                                        dao.insertDraft(LocalStoryDraft(imageData = jpeg))
                                        if (saveToPhotos) {
                                            PhotoLibrarySaver.save(context, jpeg)
                                        }
                                    }
                                    capturedJpeg = null
                                    snackbar.showSnackbar(
                                        "Pending story saved. OAuth publishing is the next slice.",
                                    )
                                }
                            },
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

        SnackbarHost(
            hostState = snackbar,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

private fun capturePhoto(
    imageCapture: ImageCapture,
    context: android.content.Context,
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
