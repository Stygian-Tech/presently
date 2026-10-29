import PhotosUI
import SwiftUI
import UIKit

public struct StoryEditorView: View {
    let session: StoryEditorSession
    var isEditable: Bool
    var onError: (String) -> Void
    var onEditingChanged: ((Bool) -> Void)? = nil

    public init(session: StoryEditorSession, isEditable: Bool = true,
                onError: @escaping (String) -> Void, onEditingChanged: ((Bool) -> Void)? = nil) {
        self.session = session
        self.isEditable = isEditable
        self.onError = onError
        self.onEditingChanged = onEditingChanged
    }

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showEmoji = false
    @State private var showTransform = false

    @State private var isEditingText = false
    @State private var textInputText = ""
    @State private var textInputStyle: StoryLayer.Style = .bold
    @State private var textInputAlignment: StoryLayer.Alignment = .center
    @State private var textInputColor: String = "white"
    @State private var textInputBackground = false
    @State private var textInputBoxWidth: Double = 1
    @State private var textInputHandle = StoryTextInputHandle()

    public var body: some View {
        ZStack {
            // Keep one canvas/input identity as controls move or the keyboard appears.
            canvasView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            if !isEditingText {
                VStack {
                    HStack(alignment: .top) {
                        StoryLayerToolbar(
                            session: session,
                            isEditable: isEditable,
                            showsSidebar: true,
                            editText: { layer in startEditingText(layer: layer) },
                            adjust: { showTransform = true }
                        )
                        .frame(width: 64)
                        Spacer(minLength: 12)
                        StoryCreationToolbar(
                            selectedPhoto: $selectedPhoto,
                            canUndo: session.canUndo,
                            addText: { startCreatingText() },
                            addEmoji: { showEmoji = true },
                            undo: { session.undo() }
                        )
                        .disabled(!isEditable || session.isImporting)
                        .frame(width: 64)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundStyle(.white)
        .onChange(of: isEditingText) { _, editing in
            onEditingChanged?(editing)
        }
        .onChange(of: textInputText) { _, newText in
            guard isEditingText, var layer = session.selectedLayer else { return }
            layer.text = newText
            session.update(layer)
        }
        .onChange(of: textInputStyle) { _, newStyle in
            guard isEditingText, var layer = session.selectedLayer else { return }
            layer.style = newStyle
            session.update(layer)
        }
        .onChange(of: textInputAlignment) { _, newAlignment in
            guard isEditingText, var layer = session.selectedLayer else { return }
            layer.alignment = newAlignment
            session.update(layer)
        }
        .onChange(of: textInputColor) { _, newColor in
            guard isEditingText, var layer = session.selectedLayer else { return }
            layer.color = newColor
            session.update(layer)
        }
        .onChange(of: textInputBoxWidth) { _, width in
            guard isEditingText, var layer = session.selectedLayer else { return }
            layer.textBoxWidth = width
            session.update(layer)
        }
        .onChange(of: textInputBackground) { _, newBackground in
            guard isEditingText, var layer = session.selectedLayer else { return }
            layer.background = newBackground
            session.update(layer)
        }
        .sensoryFeedback(.selection, trigger: session.selectedID)
        .sensoryFeedback(.impact(weight: .light), trigger: isEditingText)
        .sheet(isPresented: $showEmoji) {
            emojiSheet
        }
        .sheet(isPresented: $showTransform) {
            if let layer = session.selectedLayer {
                StoryTransformSheet(layer: layer) { session.update($0) }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            session.isImporting = true
            Task {
                defer { session.isImporting = false; selectedPhoto = nil }
                do {
                    guard let file = try await item.loadTransferable(type: StoryStickerFile.self) else { throw EditorError.invalidImage }
                    addSticker(file.data)
                } catch { onError(error.localizedDescription) }
            }
        }
    }

    private var canvasView: some View {
        StoryEditorCanvas(session: session, isEditable: isEditable, editingTextID: isEditingText ? session.selectedID : nil) { relativePoint, hitLayer, isInsidePhoto in
            handleCanvasTap(relativePoint: relativePoint, hitLayer: hitLayer, isInsidePhoto: isInsidePhoto)
        }
        .overlay {
            if session.isImporting {
                ProgressView("Adding sticker…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay {
            if isEditable {
                ZStack {
                    StoryTextInput(
                        text: $textInputText,
                        style: $textInputStyle,
                        alignment: $textInputAlignment,
                        color: $textInputColor,
                        background: $textInputBackground,
                        textBoxWidth: $textInputBoxWidth,
                        isFocused: $isEditingText,
                        handle: textInputHandle,
                        onSticker: { data in addSticker(data) },
                        onError: onError,
                        onDone: { finishEditingText() }
                    )
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var emojiSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))]) {
                    ForEach(["😀", "🥰", "😂", "😎", "🥳", "❤️", "✨", "🔥", "🌈", "☀️", "🌻", "🎉", "🐶", "🐱", "🦋", "☕️", "🍕", "📍", "💯", "🙌"], id: \.self) { emoji in
                        Button {
                            var layer = StoryLayer(text: emoji, isEmoji: true)
                            layer.width = 0.3
                            do { try session.add(layer) } catch { onError(error.localizedDescription) }
                            showEmoji = false
                        } label: { Text(emoji).font(.largeTitle).frame(minWidth: 64, minHeight: 64) }
                    }
                }.padding()
                Text("Use Text and your keyboard for more emoji.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Emoji")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showEmoji = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func handleCanvasTap(relativePoint: CGPoint, hitLayer: StoryLayer?, isInsidePhoto: Bool) {
        guard isEditable else { return }

        if isEditingText {
            finishEditingText()
            return
        }

        if let hitLayer {
            session.selectedID = hitLayer.id
            if let layer = session.selectedLayer, layer.stickerPNG == nil && !layer.isEmoji {
                startEditingText(layer: layer)
            }
        } else if isInsidePhoto {
            startCreatingText()
        }
    }

    private func startCreatingText() {
        finishEditingText()
        var newLayer = StoryLayer(text: "", x: 0.5, y: 0.5)
        newLayer.width = 0.65
        do {
            try session.add(newLayer)
            startEditingText(layer: newLayer)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func startEditingText(layer: StoryLayer) {
        textInputText = layer.text
        textInputStyle = layer.style
        textInputAlignment = layer.alignment
        textInputColor = layer.color
        textInputBackground = layer.background
        textInputBoxWidth = layer.resolvedTextBoxWidth
        isEditingText = true
    }

    private func finishEditingText() {
        guard isEditingText else { return }
        let committed = textInputHandle.committedText() ?? textInputText
        textInputText = committed

        if var layer = session.selectedLayer {
            layer.text = committed
            session.update(layer)
            if committed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.deleteSelected()
            }
        }
        isEditingText = false
        textInputHandle.blur()
    }

    private func addSticker(_ data: Data) {
        do {
            let image = try StoryRenderer.uprightImage(data, maximumDimension: 1_024, sticker: true)
            guard let png = image.pngData(), png.count <= 8 * 1_024 * 1_024 else { throw EditorError.imageTooLarge }
            var layer = StoryLayer(stickerPNG: png)
            layer.width = 0.4
            try session.add(layer)
        } catch { onError(error.localizedDescription) }
    }


}

private struct StoryTransformSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layer: StoryLayer
    let save: (StoryLayer) -> Void
    init(layer: StoryLayer, save: @escaping (StoryLayer) -> Void) {
        _layer = State(initialValue: layer)
        self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    Slider(value: $layer.x, in: 0...1) { Text("Horizontal position") }
                    Slider(value: $layer.y, in: 0...1) { Text("Vertical position") }
                    Button("Center") { layer.x = 0.5; layer.y = 0.5 }
                }
                if layer.stickerPNG == nil && !layer.isEmoji {
                    Section("Text box") {
                        Slider(value: $layer.resolvedTextBoxWidth, in: 0.35...1.5) {
                            Text("Text box width")
                        }
                        Text("Width changes line wrapping. Pinch the text on the photo to change its size.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Size and rotation") {
                    Slider(value: $layer.width, in: 0.08...1.5) { Text("Size") }
                    Slider(value: $layer.rotation, in: -.pi...Double.pi) { Text("Rotation") }
                }
            }
            .navigationTitle("Adjust layer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(layer); dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct StoryCreationToolbar: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    let canUndo: Bool
    let addText: () -> Void
    let addEmoji: () -> Void
    let undo: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                Button("Text", systemImage: "textformat", action: addText)
                Button("Emoji", systemImage: "face.smiling", action: addEmoji)
                PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                    Label("Sticker", systemImage: "photo.on.rectangle")
                }
                Divider().frame(width: 28)
                Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                    .disabled(!canUndo)
            }
            .buttonStyle(StoryPaletteButtonStyle())
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .padding(.vertical, 6)
            .labelStyle(.iconOnly)
            .modifier(PresentlyControlSurface())
            .padding(8)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: 260)
    }
}

private struct StoryLayerToolbar: View {
    let session: StoryEditorSession
    let isEditable: Bool
    let showsSidebar: Bool
    let editText: (StoryLayer) -> Void
    let adjust: () -> Void

    var body: some View {
        Group {
            if isEditable, let layer = session.selectedLayer {
                ScrollView(showsSidebar ? .vertical : .horizontal) {
                    let layout = showsSidebar
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 16))
                    layout {
                        if layer.stickerPNG == nil && !layer.isEmoji {
                            Button("Edit", systemImage: "pencil") { editText(layer) }
                        }
                        Button("Adjust", systemImage: "slider.horizontal.3", action: adjust)
                        Button("To front", systemImage: "square.3.layers.3d.top.filled") {
                            session.bringToFront()
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            session.deleteSelected()
                        }
                    }
                    .buttonStyle(StoryPaletteButtonStyle())
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.iconOnly)
                    .padding(.vertical, 6)
                    .modifier(PresentlyControlSurface())
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 248)
            } else {
                EmptyView()
            }
        }
    }
}

private struct StoryPaletteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.role == .destructive ? Color.red : Color.primary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Keep control chrome consistent while retaining support for older iOS releases.
public struct PresentlyControlSurface: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

public struct PresentlyGlassButtonStyle: ViewModifier {
    var prominent = false

    public init(prominent: Bool = false) { self.prominent = prominent }

    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
