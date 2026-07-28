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
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import tech.stygian.presently.data.AppSettings
import tech.stygian.presently.data.DefaultCamera
import tech.stygian.presently.data.LocalStoryDraft
import tech.stygian.presently.data.PresentlyDatabase
import tech.stygian.presently.story.FlashesStoryContract
import tech.stygian.presently.story.ATProtoTid
import tech.stygian.presently.oauth.AccountSheet
import tech.stygian.presently.oauth.OAuthSessionManager
import java.io.File
import java.time.Instant
import java.util.concurrent.Executors

@Composable
fun CameraRoute(auth: OAuthSessionManager) {
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
        CameraScreen(auth)
    } else {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.surface)
                .windowInsetsPadding(WindowInsets.safeDrawing),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(24.dp),
            ) {
                Text("Camera access is required to create a story.")
                Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                    Text("Allow Camera")
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CameraScreen(auth: OAuthSessionManager) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val database = remember { PresentlyDatabase.get(context) }
    val dao = remember { database.presentlyDao() }
    val settingsFlow = remember(dao) {
        dao.observeSettings().map { it ?: AppSettings() }
    }
    val settings by settingsFlow.collectAsStateWithLifecycle(initialValue = AppSettings())
    val authState by auth.state.collectAsStateWithLifecycle()
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
    var showAccount by remember { mutableStateOf(false) }
    var lensFacing by remember { mutableIntStateOf(CameraSelector.LENS_FACING_BACK) }
    var camera by remember { mutableStateOf<Camera?>(null) }
    var zoomRatio by remember { mutableFloatStateOf(1f) }
    var minimumZoomRatio by remember { mutableFloatStateOf(1f) }
    var maximumZoomRatio by remember { mutableFloatStateOf(1f) }
    var canSwitchCamera by remember { mutableStateOf(false) }
    var isPublishing by remember { mutableStateOf(false) }
    var activeDraft by remember { mutableStateOf<LocalStoryDraft?>(null) }

    fun setZoomRatio(requestedZoomRatio: Float) {
        val clampedZoomRatio = requestedZoomRatio.coerceIn(minimumZoomRatio, maximumZoomRatio)
        zoomRatio = clampedZoomRatio
        camera?.cameraControl?.setZoomRatio(clampedZoomRatio)
    }

    LaunchedEffect(settings.cameraPreference) {
        lensFacing = settings.cameraPreference.lensFacing
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
                if (!cameraProvider.hasCamera(selector)) {
                    if (lensFacing != CameraSelector.LENS_FACING_BACK) {
                        lensFacing = CameraSelector.LENS_FACING_BACK
                    }
                    return@runCatching
                }

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
            selectedDefaultCamera = settings.cameraPreference,
            onPreferenceSelected = { preference ->
                scope.launch {
                    dao.upsertSettings(
                        settings.copy(saveToPhotosPreference = preference.name),
                    )
                }
            },
            onDefaultCameraSelected = { defaultCamera ->
                scope.launch {
                    dao.upsertSettings(
                        settings.copy(defaultCamera = defaultCamera.name),
                    )
                }
            },
            onDismiss = { showSettings = false },
        )
    }
    if (showAccount) {
        AccountSheet(
            auth = auth,
            onDismiss = { showAccount = false },
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

        Box(
            modifier = Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing),
        ) {
            CameraTopBar(
                isAccountConnected = authState.session?.canPublishStory == true,
                onAccount = { showAccount = true },
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
                            onError = { message ->
                                scope.launch { snackbar.showSnackbar(message) }
                            },
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
                    isPublishing = isPublishing,
                    saveThisPhoto = saveThisPhoto,
                    onSaveThisPhotoChanged = { saveThisPhoto = it },
                    onRetake = {
                        saveThisPhoto = false
                        activeDraft = null
                        capturedJpeg = null
                    },
                    onPost = {
                        scope.launch {
                            if (jpeg.size > FlashesStoryContract.MaximumImageBytes) {
                                snackbar.showSnackbar("This image exceeds Flashes' 10 MiB limit.")
                                return@launch
                            }
                            if (authState.session?.canPublishStory != true) {
                                showAccount = true
                                return@launch
                            }

                            val draft = activeDraft?.copy(
                                state = LocalStoryDraft.State.Publishing.storageValue,
                                lastError = null,
                            ) ?: LocalStoryDraft(
                                imageData = jpeg,
                                state = LocalStoryDraft.State.Publishing.storageValue,
                                recordKey = ATProtoTid.create(),
                            ).also { activeDraft = it }
                            dao.upsertDraft(draft)
                            activeDraft = draft
                            val recordKey = checkNotNull(draft.recordKey)
                            isPublishing = true
                            try {
                                val published = auth.publishStory(
                                    jpegData = jpeg,
                                    createdAt = Instant.ofEpochMilli(
                                        draft.createdAtEpochMillis,
                                    ),
                                    recordKey = recordKey,
                                )
                                dao.upsertDraft(
                                    draft.copy(
                                        state = LocalStoryDraft.State.Published.storageValue,
                                        publishedUri = published.uri,
                                        publishedCid = published.cid,
                                        lastError = null,
                                    ),
                                )

                                val shouldSave =
                                    settings.preference.shouldSave(saveThisPhoto)
                                val message = if (shouldSave) {
                                    runCatching {
                                        PhotoLibrarySaver.save(context, jpeg)
                                    }.fold(
                                        onSuccess = {
                                            "Your Story Is Live and Saved to Photos."
                                        },
                                        onFailure = {
                                            "Your Story Is Live, but It Couldn’t Be Saved to Photos."
                                        },
                                    )
                                } else {
                                    "Your Story Is Live."
                                }
                                saveThisPhoto = false
                                activeDraft = null
                                capturedJpeg = null
                                snackbar.showSnackbar(message)
                            } catch (error: Throwable) {
                                val detail = error.localizedMessage
                                    ?: "The story could not be posted."
                                val failed = draft.copy(
                                    state = LocalStoryDraft.State.Failed.storageValue,
                                    lastError = detail,
                                )
                                dao.upsertDraft(failed)
                                activeDraft = failed
                                snackbar.showSnackbar(
                                    "Your Story Couldn’t Be Posted. Tap the Checkmark to Try Again.",
                                )
                            } finally {
                                isPublishing = false
                            }
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
}

private fun capturePhoto(
    imageCapture: ImageCapture,
    context: Context,
    onCaptured: (ByteArray) -> Unit,
    onError: (String) -> Unit,
) {
    val outputFile = File.createTempFile("presently-", ".jpg", context.cacheDir)
    val options = ImageCapture.OutputFileOptions.Builder(outputFile).build()
    val captureExecutor = Executors.newSingleThreadExecutor()
    val mainExecutor = ContextCompat.getMainExecutor(context)

    imageCapture.takePicture(
        options,
        captureExecutor,
        object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                runCatching {
                    JpegOrientationNormalizer.normalize(outputFile.readBytes())
                }
                    .onSuccess { data ->
                        mainExecutor.execute { onCaptured(data) }
                    }
                    .onFailure { error ->
                        mainExecutor.execute {
                            onError(
                                error.localizedMessage
                                    ?: "Could not read captured photo.",
                            )
                        }
                    }
                outputFile.delete()
                captureExecutor.shutdown()
            }

            override fun onError(exception: ImageCaptureException) {
                outputFile.delete()
                captureExecutor.shutdown()
                mainExecutor.execute {
                    onError(exception.localizedMessage ?: "Could not capture photo.")
                }
            }
        },
    )
}

private val DefaultCamera.lensFacing: Int
    get() = when (this) {
        DefaultCamera.REAR -> CameraSelector.LENS_FACING_BACK
        DefaultCamera.FRONT -> CameraSelector.LENS_FACING_FRONT
    }
