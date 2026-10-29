package tech.stygian.presently.camera

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.browser.customtabs.CustomTabsIntent
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import tech.stygian.presently.editor.StoryComposition
import tech.stygian.presently.editor.StoryLayer
import tech.stygian.presently.editor.StoryEditor
import tech.stygian.presently.editor.StoryEditorStore
import tech.stygian.presently.data.AppSettings
import tech.stygian.presently.PresentlyLinks
import tech.stygian.presently.data.DefaultCamera
import tech.stygian.presently.data.LocalStoryDraft
import tech.stygian.presently.data.PresentlyDatabase
import tech.stygian.presently.oauth.AccountSheet
import tech.stygian.presently.oauth.OAuthSessionManager
import java.io.File
import java.time.Instant
import java.util.concurrent.Executors

@Composable
fun CameraRoute(auth: OAuthSessionManager) {
    val context = LocalContext.current
    val activity = LocalActivity.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    var cameraPermissionRequestCompleted by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        hasCameraPermission = granted
        cameraPermissionRequestCompleted = true
    }
    val appSettingsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) {
        hasCameraPermission =
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        cameraPermissionRequestCompleted = !hasCameraPermission
    }
    val permissionAction = cameraPermissionAction(
        hasPermission = hasCameraPermission,
        permissionRequestCompleted = cameraPermissionRequestCompleted,
        shouldShowRationale = activity?.let {
            ActivityCompat.shouldShowRequestPermissionRationale(
                it,
                Manifest.permission.CAMERA,
            )
        } ?: false,
    )

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) {
            cameraPermissionRequestCompleted = false
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
                Text(
                    if (permissionAction == CameraPermissionAction.OPEN_APP_SETTINGS) {
                        "Camera access is turned off. Enable it in Settings to create a story."
                    } else {
                        "Camera access is required to create a story."
                    },
                )
                Button(
                    onClick = {
                        if (permissionAction == CameraPermissionAction.OPEN_APP_SETTINGS) {
                            appSettingsLauncher.launch(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.fromParts("package", context.packageName, null)
                                },
                            )
                        } else {
                            cameraPermissionRequestCompleted = false
                            permissionLauncher.launch(Manifest.permission.CAMERA)
                        }
                    },
                ) {
                    Text(
                        if (permissionAction == CameraPermissionAction.OPEN_APP_SETTINGS) {
                            "Open Settings"
                        } else {
                            "Allow Camera"
                        },
                    )
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
    val currentActivity = LocalActivity.current
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
    var pendingLegacyPhotoPermissionAction by remember {
        mutableStateOf<(() -> Unit)?>(null)
    }
    var skipLegacyPhotoSaveOnce by remember { mutableStateOf(false) }
    val legacyPhotoPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val pendingAction = pendingLegacyPhotoPermissionAction
        pendingLegacyPhotoPermissionAction = null
        if (pendingAction != null) {
            skipLegacyPhotoSaveOnce = !granted
            pendingAction()
        }
    }
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
    val editorStore = remember { StoryEditorStore(context.applicationContext, dao) }
    val editorWrites = remember { Mutex() }
    var composition by remember { mutableStateOf(StoryComposition()) }
    var stickerAssets by remember { mutableStateOf<Map<String, android.graphics.Bitmap>>(emptyMap()) }
    var editorReady by remember { mutableStateOf(false) }
    var editorTransforming by remember { mutableStateOf(false) }
    var editorBusy by remember { mutableStateOf(false) }
    var pendingEditorWrites by remember { mutableIntStateOf(0) }

    fun reportEditorError(error: Throwable) {
        scope.launch { snackbar.showSnackbar(error.localizedMessage ?: "The story could not be edited.") }
    }

    fun updateComposition(next: StoryComposition) {
        composition = next
        pendingEditorWrites += 1
        scope.launch {
            try {
                editorWrites.withLock {
                    activeDraft?.let {
                        val needed = next.layers.mapNotNull { layer -> layer.asset }.toSet()
                        if (!stickerAssets.keys.containsAll(needed)) stickerAssets = editorStore.loadAssets(it, next)
                        activeDraft = editorStore.save(it, next)
                    }
                }
            } catch (error: Exception) { reportEditorError(error) }
            finally { pendingEditorWrites -= 1 }
        }
    }

    LaunchedEffect(Unit) {
        try {
            var restored = editorStore.restore()
            if (restored == null &&
                context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
                currentActivity?.intent?.getBooleanExtra("presently.editor.sample", false) == true
            ) {
                val sample = android.graphics.Bitmap.createBitmap(1200, 1600, android.graphics.Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(sample)
                canvas.drawPaint(android.graphics.Paint().apply {
                    shader = android.graphics.LinearGradient(0f, 0f, 1200f, 1600f, 0xFF245D77.toInt(), 0xFFE7B784.toInt(), android.graphics.Shader.TileMode.CLAMP)
                })
                val data = java.io.ByteArrayOutputStream().use { output -> sample.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, output); output.toByteArray() }
                sample.recycle()
                restored = editorStore.create(data)
                currentActivity.intent.removeExtra("presently.editor.sample")
            }
            if (restored != null) {
                activeDraft = restored
                composition = StoryComposition.decode(restored.compositionJson)
                capturedJpeg = editorStore.source(restored)
                stickerAssets = editorStore.loadAssets(restored, composition)
            }
        } catch (error: Exception) { reportEditorError(error) }
        finally { editorReady = true }
    }
    DisposableEffect(stickerAssets) {
        val old = stickerAssets
        onDispose { old.values.forEach { it.recycle() } }
    }


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
            onOpenFeedbackBoard = {
                if (!openExternalLink(context, PresentlyLinks.FeedbackBoard)) {
                    scope.launch {
                        snackbar.showSnackbar("Could not open the feedback board.")
                    }
                }
            },
            onOpenPrivacyPolicy = {
                if (!openExternalLink(context, PresentlyLinks.PrivacyPolicy)) {
                    scope.launch {
                        snackbar.showSnackbar("Could not open the privacy policy.")
                    }
                }
            },
            onOpenTerms = {
                if (!openExternalLink(context, PresentlyLinks.Terms)) {
                    scope.launch {
                        snackbar.showSnackbar("Could not open the terms.")
                    }
                }
            },
            onOpenSupport = {
                if (!openExternalLink(context, PresentlyLinks.Support)) {
                    scope.launch {
                        snackbar.showSnackbar("Could not open support.")
                    }
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
            val draft = activeDraft
            if (draft != null) StoryEditor(
                jpeg = jpeg,
                draftId = draft.id,
                composition = composition,
                assets = stickerAssets,
                frozen = draft.renderedImagePath != null || draft.recordKey != null,
                editable = !isPublishing && !editorBusy && draft.renderedImagePath == null && draft.recordKey == null,
                onChange = ::updateComposition,
                onTransforming = { editorTransforming = it },
                onImport = { uri, finished ->
                    if (composition.layers.size >= StoryComposition.MaximumLayers || composition.layers.count { it.asset != null } >= 10) {
                        finished()
                        scope.launch { snackbar.showSnackbar("A story can have up to 30 layers, including 10 image stickers.") }
                    } else {
                        editorBusy = true
                        scope.launch {
                            try {
                                editorWrites.withLock {
                                    val currentDraft = checkNotNull(activeDraft)
                                    val asset = editorStore.importSticker(currentDraft, uri)
                                    val next = composition.copy(layers = composition.layers + StoryLayer(asset = asset))
                                    val loaded = editorStore.loadAssets(currentDraft, next)
                                    activeDraft = editorStore.save(currentDraft, next)
                                    stickerAssets = loaded
                                    composition = next
                                }
                            } catch (error: Exception) { reportEditorError(error) }
                            finally { editorBusy = false; finished() }
                        }
                    }
                },
                onError = { message -> scope.launch { snackbar.showSnackbar(message) } },
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
                    onCapture = capture@{
                        if (!editorReady || editorBusy) return@capture
                        editorBusy = true
                        saveThisPhoto = false
                        capturePhoto(
                            imageCapture = imageCapture,
                            context = context,
                            onCaptured = { bytes ->
                                scope.launch {
                                    try {
                                        activeDraft = editorStore.create(bytes)
                                        composition = StoryComposition()
                                        stickerAssets = emptyMap()
                                        capturedJpeg = bytes
                                    } catch (error: Exception) { reportEditorError(error) }
                                    finally { editorBusy = false }
                                }
                            },
                            onError = { message ->
                                editorBusy = false
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
                    interactionBlocked = editorBusy || editorTransforming || pendingEditorWrites > 0,
                    saveThisPhoto = saveThisPhoto,
                    onSaveThisPhotoChanged = { saveThisPhoto = it },
                    onRetake = {
                        saveThisPhoto = false
                        editorBusy = true
                        scope.launch {
                            try {
                                editorWrites.withLock { activeDraft?.let { editorStore.discard(it) } }
                                activeDraft = null
                                capturedJpeg = null
                                composition = StoryComposition()
                                stickerAssets = emptyMap()
                            } catch (error: Exception) { reportEditorError(error) }
                            finally { editorBusy = false }
                        }
                    },
                    onPost = post@{
                        if (isPublishing || editorBusy || editorTransforming || pendingEditorWrites > 0) return@post
                        val shouldSavePhoto = settings.preference.shouldSave(saveThisPhoto)
                        val publishAction: () -> Unit = {
                            scope.launch {
                                if (authState.session?.canPublishStory != true) {
                                    showAccount = true
                                    return@launch
                                }

                                isPublishing = true
                                var attemptDraft: LocalStoryDraft? = null
                                try {
                                    val (frozen, export) = editorWrites.withLock {
                                        editorStore.freeze(checkNotNull(activeDraft), composition)
                                    }
                                    val draft = frozen.copy(state = LocalStoryDraft.State.Publishing.storageValue, lastError = null)
                                    dao.upsertDraft(draft)
                                    activeDraft = draft
                                    attemptDraft = draft
                                    val recordKey = checkNotNull(draft.recordKey)
                                    val published = auth.publishStory(
                                        jpegData = export,
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

                                    val shouldSave = shouldSavePhoto && !skipLegacyPhotoSaveOnce
                                    val message = if (shouldSave) {
                                        runCatching {
                                            PhotoLibrarySaver.save(context, export)
                                        }.fold(
                                            onSuccess = {
                                                "Your Story Is Live and Saved to Photos."
                                            },
                                            onFailure = {
                                                "Your Story Is Live, but It Couldn’t Be Saved to Photos."
                                            },
                                        )
                                    } else if (shouldSavePhoto) {
                                        "Your Story Is Live, but It Couldn’t Be Saved to Photos."
                                    } else {
                                        "Your Story Is Live."
                                    }
                                    saveThisPhoto = false
                                    activeDraft = null
                                    capturedJpeg = null
                                    composition = StoryComposition()
                                    stickerAssets = emptyMap()
                                    snackbar.showSnackbar(message)
                                } catch (error: Throwable) {
                                    val detail = error.localizedMessage
                                        ?: "The story could not be posted."
                                    attemptDraft?.let { draft ->
                                        val failed = draft.copy(
                                            state = LocalStoryDraft.State.Failed.storageValue,
                                            lastError = detail,
                                        )
                                        dao.upsertDraft(failed)
                                        activeDraft = failed
                                    }
                                    snackbar.showSnackbar(
                                        "Your Story Couldn’t Be Posted. Tap the Checkmark to Try Again.",
                                    )
                                } finally {
                                    isPublishing = false
                                    skipLegacyPhotoSaveOnce = false
                                }
                            }
                        }
                        val hasLegacyPhotoPermission =
                            ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.WRITE_EXTERNAL_STORAGE,
                            ) == PackageManager.PERMISSION_GRANTED
                        if (
                            shouldRequestLegacyPhotoLibraryPermission(
                                sdkInt = Build.VERSION.SDK_INT,
                                shouldSavePhoto = shouldSavePhoto,
                                hasPermission = hasLegacyPhotoPermission,
                            )
                        ) {
                            pendingLegacyPhotoPermissionAction = publishAction
                            legacyPhotoPermissionLauncher.launch(
                                Manifest.permission.WRITE_EXTERNAL_STORAGE,
                            )
                            return@post
                        }
                        publishAction()
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

private fun openExternalLink(context: Context, url: String): Boolean {
    val uri = Uri.parse(url)
    val openedInCustomTab = runCatching {
        CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
            .launchUrl(context, uri)
    }.isSuccess

    if (openedInCustomTab) return true

    return runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE),
        )
    }.isSuccess
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
