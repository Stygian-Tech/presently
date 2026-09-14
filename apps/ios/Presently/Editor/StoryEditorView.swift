import PhotosUI
import SwiftUI
import UIKit

struct StoryEditorView: View {
    let session: StoryEditorSession
    var isEditable: Bool
    var onError: (String) -> Void
    @State private var editingLayer: StoryLayer?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showEmoji = false
    @State private var showTransform = false


    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    Button("Text", systemImage: "textformat") { editingLayer = StoryLayer() }
                    Button("Emoji", systemImage: "face.smiling") { showEmoji = true }
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                        Label("Sticker", systemImage: "photo.on.rectangle")
                    }
                    Button("Undo", systemImage: "arrow.uturn.backward") { session.undo() }
                        .disabled(!session.canUndo)
                }
                .padding()
            }
            .disabled(!isEditable || session.isImporting)
            .background(.black.opacity(0.7))

            StoryEditorCanvas(session: session, isEditable: isEditable)
                .overlay {
                    if session.isImporting { ProgressView("Adding sticker…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                }

            if isEditable, let layer = session.selectedLayer {
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        if layer.stickerPNG == nil && !layer.isEmoji {
                            Button("Edit", systemImage: "pencil") { editingLayer = layer }
                        }
                        Button("Adjust", systemImage: "slider.horizontal.3") { showTransform = true }
                        Button("To front", systemImage: "square.3.layers.3d.top.filled") { session.bringToFront() }
                        Button("Delete", systemImage: "trash", role: .destructive) { session.deleteSelected() }
                    }
                    .padding()
                }
            } else {
                Text(isEditable ? "Drag to move · Pinch to resize · Twist to rotate" : "This version is saved for retrying your post.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .foregroundStyle(.white)
        .sheet(item: $editingLayer) { layer in
            StoryTextSheet(layer: layer, existingComposition: session.composition, saveSticker: { data in
                addSticker(data)
            }, onError: onError) { updated in
                do {
                    if session.composition.layers.contains(where: { $0.id == updated.id }) { session.update(updated) }
                    else { try session.add(updated) }
                } catch { onError(error.localizedDescription) }
            }
        }
        .sheet(isPresented: $showEmoji) {
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

private struct StoryTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var layer: StoryLayer
    @State private var pendingStickers: [Data] = []
    @State private var textInput = StoryTextInputHandle()
    let existingComposition: StoryComposition
    let saveSticker: (Data) -> Void
    let onError: (String) -> Void
    let save: (StoryLayer) -> Void

    init(layer: StoryLayer, existingComposition: StoryComposition, saveSticker: @escaping (Data) -> Void, onError: @escaping (String) -> Void, save: @escaping (StoryLayer) -> Void) {
        _layer = State(initialValue: layer)
        self.existingComposition = existingComposition
        self.saveSticker = saveSticker
        self.onError = onError
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    StoryTextInput(text: $layer.text, handle: textInput, onSticker: { data in
                        do {
                            guard pendingStickers.count < 30 else { throw EditorError.tooManyLayers }
                            let image = try StoryRenderer.uprightImage(data, maximumDimension: 1_024, sticker: true)
                            guard let png = image.pngData() else { throw EditorError.invalidImage }
                            var proposed = existingComposition
                            proposed.layers += (pendingStickers + [png]).map { StoryLayer(stickerPNG: $0) }
                            guard proposed.layers.count <= 30, proposed.fitsAssetBudget else { throw EditorError.imageTooLarge }
                            pendingStickers.append(png)
                        } catch { onError(error.localizedDescription) }
                    }, onError: onError)
                    .frame(minHeight: 100)
                    if !pendingStickers.isEmpty {
                        Text("\(pendingStickers.count) keyboard sticker(s) ready to add").font(.caption)
                    }
                    Text("\(layer.text.count)/500 characters").font(.caption).foregroundStyle(.secondary)
                }
                Section("Style") {
                    Picker("Font", selection: $layer.style) {
                        ForEach(StoryLayer.Style.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Alignment", selection: $layer.alignment) {
                        ForEach(StoryLayer.Alignment.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Color", selection: $layer.color) {
                        ForEach(StoryRenderer.colors, id: \.0) { color in
                            Text(color.0.capitalized).tag(color.0)
                        }
                    }
                    Toggle("Background", isOn: $layer.background)
                }
                Section("Preview") {
                    Image(uiImage: StoryRenderer.layerImage(layer))
                        .resizable().scaledToFit().frame(maxHeight: 140)
                        .frame(maxWidth: .infinity)
                        .background(.gray.opacity(0.35))
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle("Text")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var committedLayer = layer
                        committedLayer.text = textInput.committedText() ?? layer.text
                        if !committedLayer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { save(committedLayer) }
                        for sticker in pendingStickers { saveSticker(sticker) }
                        dismiss()
                    }
                    .disabled(layer.text.count > 500)
                }
            }

        }
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
