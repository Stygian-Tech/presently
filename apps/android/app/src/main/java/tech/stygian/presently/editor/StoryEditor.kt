package tech.stygian.presently.editor

import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.EditText
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.inputmethod.EditorInfoCompat
import androidx.core.view.inputmethod.InputConnectionCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
internal fun StoryEditor(
    jpeg: ByteArray,
    draftId: String,
    composition: StoryComposition,
    assets: Map<String, Bitmap>,
    editable: Boolean,
    frozen: Boolean,
    onChange: (StoryComposition) -> Unit,
    onImport: (Uri, () -> Unit) -> Unit,
    onError: (String) -> Unit,
    onTransforming: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    var bitmap by remember(jpeg) { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(jpeg) {
        runCatching { withContext(Dispatchers.Default) { StoryEditorStore.decodeBounded(jpeg, 2048) } }
            .onSuccess { bitmap = it }.onFailure { onError(it.localizedMessage ?: "This photo could not be opened.") }
    }
    DisposableEffect(bitmap) { val old = bitmap; onDispose { old?.recycle() } }
    var selectedId by remember(draftId) { mutableStateOf<String?>(null) }
    var showLayers by remember(draftId) { mutableStateOf(false) }
    var editing by remember(draftId) { mutableStateOf<StoryLayer?>(null) }
    val undo = remember(draftId) { mutableStateListOf<StoryComposition>() }
    var lastComposition by remember(draftId) { mutableStateOf(composition) }
    LaunchedEffect(composition) {
        val added = composition.layers.filter { layer -> lastComposition.layers.none { it.id == layer.id } }
        if (added.isNotEmpty() && composition != lastComposition) {
            undo.add(lastComposition)
            if (undo.size > 30) undo.removeAt(0)
            selectedId = added.last().id
        }
        lastComposition = composition
    }
    val selected = composition.layers.find { it.id == selectedId }
    fun change(next: StoryComposition) {
        if (next == composition || !editable) return
        undo.add(composition)
        if (undo.size > 30) undo.removeAt(0)
        lastComposition = next
        onChange(next)
    }
    fun add(layer: StoryLayer) {
        if (composition.layers.size >= StoryComposition.MaximumLayers) { onError("A story can have up to 30 layers."); return }
        change(composition.copy(layers = composition.layers + layer)); selectedId = layer.id
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { onImport(it) {} } }
    Box(Modifier.fillMaxSize()) {
        AndroidView(
            factory = { StoryCanvasView(it) },
            update = { view ->
                view.source = bitmap; view.assets = assets; view.editable = editable
                if (!view.transforming) { view.composition = composition; view.selectedId = selectedId }
                view.onTransforming = onTransforming
                view.onSelect = { selectedId = it }
                view.onChange = { change(it) }
                view.onEdit = { editing = it }
                view.invalidate()
            },
            modifier = Modifier.fillMaxSize(),
        )
        Column(Modifier.align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing).padding(top = 64.dp)) {
            Surface(color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f), shape = MaterialTheme.shapes.large) {
                Column {
                    Row(Modifier.horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
                        TextButton(enabled = editable, onClick = { editing = StoryLayer() }) { Text("Text") }
                        TextButton(enabled = editable, onClick = { editing = StoryLayer(text = "✨", scale = 2.5f) }) { Text("Emoji") }
                        TextButton(enabled = editable, onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text("Sticker") }
                        TextButton(enabled = editable, onClick = {
                            val clip = (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
                            val uri = if (clip != null && clip.itemCount > 0) clip.getItemAt(0).uri else null
                            if (uri != null) onImport(uri) {} else onError("Copy an image to paste it as a sticker.")
                        }) { Text("Paste") }
                        TextButton(enabled = editable && composition.layers.isNotEmpty(), onClick = { showLayers = true }) { Text("Layers") }
                        TextButton(enabled = editable && undo.isNotEmpty(), onClick = { val previous = undo.removeAt(undo.lastIndex); lastComposition = previous; onChange(previous); selectedId = null }) { Text("Undo") }
                    }
                    if (selected != null && editable) Row(Modifier.horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
                        if (selected.asset == null) TextButton(onClick = { editing = selected }) { Text("Edit") }
                        TextButton(onClick = { change(composition.copy(layers = composition.layers.map { if (it.id == selected.id) it.copy(x = 0.5f, y = 0.5f) else it })) }) { Text("Center") }
                        TextButton(onClick = { change(composition.copy(layers = composition.layers.map { if (it.id == selected.id) it.transformed(0f, 0f, 0.85f, 0f) else it })) }) { Text("Smaller") }
                        TextButton(onClick = { change(composition.copy(layers = composition.layers.map { if (it.id == selected.id) it.transformed(0f, 0f, 1.15f, 0f) else it })) }) { Text("Larger") }
                        TextButton(onClick = { change(composition.copy(layers = composition.layers.map { if (it.id == selected.id) it.transformed(0f, 0f, 1f, 15f) else it })) }) { Text("Rotate") }
                        listOf("Left" to (-0.03f to 0f), "Right" to (0.03f to 0f), "Up" to (0f to -0.03f), "Down" to (0f to 0.03f)).forEach { (label, offset) ->
                            TextButton(onClick = { change(composition.copy(layers = composition.layers.map { if (it.id == selected.id) it.transformed(offset.first, offset.second, 1f, 0f) else it })) }) { Text(label) }
                        }
                        TextButton(onClick = { change(composition.copy(layers = composition.layers.filter { it.id != selected.id })); selectedId = null }) { Text("Delete") }
                    }
                    if (frozen) Text("This story is ready to retry. Its edits are saved.", modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp), style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
    if (showLayers) AlertDialog(
        onDismissRequest = { showLayers = false }, title = { Text("Choose a layer") },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) {
            composition.layers.forEachIndexed { index, layer -> TextButton(onClick = { selectedId = layer.id; showLayers = false }) {
                Text(if (layer.asset == null) "${index + 1}. ${layer.text.take(40)}" else "${index + 1}. Image sticker")
            } }
        } }, confirmButton = { TextButton(onClick = { showLayers = false }) { Text("Close") } },
    )
    editing?.let { layer ->
        TextLayerDialog(layer, onDismiss = { editing = null }, onSticker = { uri, finished -> onImport(uri, finished); editing = null }, onDone = { updated ->
            if (composition.layers.any { it.id == updated.id }) change(composition.copy(layers = composition.layers.map { if (it.id == updated.id) updated else it }))
            else add(updated)
            editing = null
        })
    }
}

@Composable
private fun TextLayerDialog(initial: StoryLayer, onDismiss: () -> Unit, onSticker: (Uri, () -> Unit) -> Unit, onDone: (StoryLayer) -> Unit) {
    var style by remember { mutableStateOf(initial.style) }
    var alignment by remember { mutableStateOf(initial.alignment) }
    var background by remember { mutableStateOf(initial.background) }
    var color by remember { mutableIntStateOf(initial.color) }
    var input by remember { mutableStateOf<StickerEditText?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit text") },
        text = { Column(Modifier.verticalScroll(rememberScrollState())) {
            AndroidView(factory = { context -> StickerEditText(context).apply {
                setText(initial.text); hint = "Type text or use emoji"; minLines = 2; maxLines = 5
                filters = arrayOf(android.text.InputFilter.LengthFilter(StoryComposition.MaximumTextLength))
                onStickerReceived = onSticker; input = this
                setSelection(text.length)
            } }, modifier = Modifier.fillMaxWidth())
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                listOf("bold", "classic", "mono").forEach { value -> FilterChip(selected = style == value, onClick = { style = value }, label = { Text(value.replaceFirstChar { it.uppercase() }) }) }
            }
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                listOf("left", "center", "right").forEach { value -> FilterChip(selected = alignment == value, onClick = { alignment = value }, label = { Text(value.replaceFirstChar { it.uppercase() }) }) }
            }
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                listOf("White" to android.graphics.Color.WHITE, "Black" to android.graphics.Color.BLACK, "Yellow" to android.graphics.Color.YELLOW, "Pink" to 0xFFFF80AB.toInt(), "Blue" to 0xFF80D8FF.toInt()).forEach { (name, value) ->
                    FilterChip(selected = color == value, onClick = { color = value }, label = { Text(name) })
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(checked = background, onCheckedChange = { background = it }); Text("Text background") }
        } },
        confirmButton = { TextButton(onClick = { val text = input?.text?.toString()?.trim().orEmpty(); if (text.isNotEmpty()) onDone(initial.copy(text = text, style = style, alignment = alignment, color = color, background = background)) }) { Text("Done") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** IME-provided sticker URIs are copied immediately into the draft's private storage. */
private class StickerEditText(context: Context) : EditText(context) {
    var onStickerReceived: (Uri, () -> Unit) -> Unit = { _, finished -> finished() }
    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
        val connection = super.onCreateInputConnection(outAttrs) ?: return null
        EditorInfoCompat.setContentMimeTypes(outAttrs, arrayOf("image/png", "image/jpeg", "image/webp"))
        @Suppress("DEPRECATION")
        return InputConnectionCompat.createWrapper(connection, outAttrs) { content, flags, _ ->
            if (flags and InputConnectionCompat.INPUT_CONTENT_GRANT_READ_URI_PERMISSION != 0) {
                try { content.requestPermission() } catch (_: Exception) { return@createWrapper false }
            }
            onStickerReceived(content.contentUri) { runCatching { content.releasePermission() } }
            true
        }
    }
    override fun onTextContextMenuItem(id: Int): Boolean {
        if (id == android.R.id.paste) {
            val clip = (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
            val uri = if (clip != null && clip.itemCount > 0) clip.getItemAt(0).uri else null
            if (uri != null) { onStickerReceived(uri) {}; return true }
        }
        return super.onTextContextMenuItem(id)
    }
}
