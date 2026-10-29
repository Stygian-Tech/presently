import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct StoryKeyboardToolbarView: View {
    @Binding var style: StoryLayer.Style
    @Binding var alignment: StoryLayer.Alignment
    @Binding var color: String
    @Binding var background: Bool
    var onDone: () -> Void

    @Binding var textBoxWidth: Double

    @State private var showsColors = false
    @State private var showsWidth = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Menu {
                    Picker("Font", selection: $style) {
                        ForEach(StoryLayer.Style.allCases, id: \.self) { font in
                            Text(font.title).tag(font)
                        }
                    }
                } label: {
                    Image(systemName: "textformat")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Font")
                .accessibilityValue(Text(style.title))

                Menu {
                    Picker("Alignment", selection: $alignment) {
                        Text("Left").tag(StoryLayer.Alignment.left)
                        Text("Center").tag(StoryLayer.Alignment.center)
                        Text("Right").tag(StoryLayer.Alignment.right)
                    }
                    Toggle("Text background", isOn: $background)
                } label: {
                    Image(systemName: alignmentIcon(alignment))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Text options")

                Button {
                    showsColors.toggle()
                } label: {
                    Circle()
                        .fill(Color(StoryRenderer.textColor(color)))
                        .frame(width: 24, height: 24)
                        .overlay { Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1) }
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Text color")
                .accessibilityValue(color)
                .sheet(isPresented: $showsColors) {
                    VStack(spacing: 12) {
                        StoryTextColorPalette(color: $color)
                        Divider()
                        ColorPicker("Custom color", selection: Binding(
                            get: { Color(StoryRenderer.textColor(color)) },
                            set: { color = StoryRenderer.colorValue(UIColor($0)) }
                        ), supportsOpacity: false)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .presentationDetents([.height(180)])
                    .presentationDragIndicator(.visible)
                }

                Button {
                    showsWidth.toggle()
                } label: {
                    Image(systemName: "arrow.left.and.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Text box width")
                .popover(isPresented: $showsWidth) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Text box width").font(.headline)
                        Slider(value: $textBoxWidth, in: 0.35...1.5) {
                            Text("Text box width")
                        }
                        .accessibilityValue(Text(textBoxWidth, format: .percent.precision(.fractionLength(0))))
                    }
                    .frame(width: 240)
                    .padding()
                    .presentationCompactAdaptation(.popover)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .modifier(PresentlyControlSurface())

            Button("Done", systemImage: "checkmark", action: onDone)
                .labelStyle(.iconOnly)
                .modifier(PresentlyGlassButtonStyle(prominent: true))
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .environment(\.colorScheme, .dark)
    }

    private func alignmentIcon(_ alignment: StoryLayer.Alignment) -> String {
        switch alignment {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        }
    }
}

private struct StoryTextColorPalette: View {
    @Binding var color: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(StoryRenderer.colors, id: \.0) { name, uiColor in
                    Button {
                        color = name
                    } label: {
                        Circle()
                            .fill(Color(uiColor))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
                            }
                            .padding(4)
                            .overlay {
                                Circle().strokeBorder(.white, lineWidth: color == name ? 2 : 0)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(name)")
                    .accessibilityAddTraits(color == name ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .frame(height: 44)
    }
}

final class KeyboardAccessoryHostingView<Content: View>: UIView {
    let hostingController: UIHostingController<Content>

    init(rootView: Content) {
        self.hostingController = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .clear
        isOpaque = false
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }
}

struct StoryTextInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var style: StoryLayer.Style
    @Binding var alignment: StoryLayer.Alignment
    @Binding var color: String
    @Binding var background: Bool
    @Binding var textBoxWidth: Double
    @Binding var isFocused: Bool
    var handle: StoryTextInputHandle? = nil
    let onSticker: (Data) -> Void
    let onError: (String) -> Void
    let onDone: () -> Void

    init(
        text: Binding<String>,
        style: Binding<StoryLayer.Style> = .constant(.bold),
        alignment: Binding<StoryLayer.Alignment> = .constant(.center),
        color: Binding<String> = .constant("white"),
        background: Binding<Bool> = .constant(false),
        textBoxWidth: Binding<Double> = .constant(1),
        isFocused: Binding<Bool> = .constant(false),
        handle: StoryTextInputHandle? = nil,
        onSticker: @escaping (Data) -> Void = { _ in },
        onError: @escaping (String) -> Void = { _ in },
        onDone: @escaping () -> Void = {}
    ) {
        self._text = text
        self._style = style
        self._alignment = alignment
        self._color = color
        self._background = background
        self._textBoxWidth = textBoxWidth
        self._isFocused = isFocused
        self.handle = handle
        self.onSticker = onSticker
        self.onError = onError
        self.onDone = onDone
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.pasteDelegate = context.coordinator
        view.allowsEditingTextAttributes = true
        if #available(iOS 18.0, *) { view.supportsAdaptiveImageGlyph = true }
        view.accessibilityLabel = "Sticker text"
        view.text = text

        let toolbarView = StoryKeyboardToolbarView(
            style: $style,
            alignment: $alignment,
            color: $color,
            background: $background,
            onDone: onDone,
            textBoxWidth: $textBoxWidth
        )
        let accessoryView = KeyboardAccessoryHostingView(rootView: toolbarView)
        view.inputAccessoryView = accessoryView

        handle?.textView = view
        handle?.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if let accessory = view.inputAccessoryView as? KeyboardAccessoryHostingView<StoryKeyboardToolbarView> {
            accessory.hostingController.rootView = StoryKeyboardToolbarView(
                style: $style, alignment: $alignment, color: $color,
                background: $background, onDone: onDone, textBoxWidth: $textBoxWidth
            )
        }
        context.coordinator.synchronize(view, modelText: text)

        if isFocused {
            if !view.isFirstResponder {
                view.becomeFirstResponder()
            }
        } else {
            if view.isFirstResponder {
                view.resignFirstResponder()
            }
        }
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: StoryTextInput
        init(_ parent: StoryTextInput) { self.parent = parent }

        func synchronize(_ textView: UITextView, modelText: String) {
            guard !textView.isFirstResponder, textView.markedTextRange == nil,
                  textView.text != modelText else { return }
            let selection = textView.selectedRange
            textView.text = modelText
            restoreSelection(selection, in: textView)
        }

        private func restoreSelection(_ selection: NSRange, in textView: UITextView) {
            let length = textView.text.utf16.count
            let location = min(selection.location, length)
            textView.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            textViewDidChange(textView)
            // Commit the layer while the editor still considers this an active edit.
            parent.onDone()
            parent.isFocused = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if textView.markedTextRange != nil { return true }
            guard let swiftRange = Range(range, in: textView.text) else { return false }
            let proposed = textView.text.replacingCharacters(in: swiftRange, with: text)
            guard proposed.count <= 500 else {
                parent.onError("Text can contain up to 500 characters.")
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            let selection = textView.selectedRange
            let text = NSMutableAttributedString(attributedString: textView.attributedText)
            var ranges: [NSRange] = []
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
                if #available(iOS 18.0, *), let glyph = attributes[.adaptiveImageGlyph] as? NSAdaptiveImageGlyph {
                    parent.onSticker(glyph.imageContent)
                    ranges.append(range)
                } else if let attachment = attributes[.attachment] as? NSTextAttachment {
                    if let data = attachment.contents ?? attachment.image?.pngData() { parent.onSticker(data) }
                    else { parent.onError("This keyboard sticker could not be opened. Try adding it from Photos.") }
                    ranges.append(range)
                }
            }
            for range in ranges.reversed() { text.deleteCharacters(in: range) }
            if !ranges.isEmpty {
                let mapOffset: (Int) -> Int = { offset in
                    offset - ranges.reduce(0) { removed, range in
                        removed + min(range.length, max(0, offset - range.location))
                    }
                }
                let start = mapOffset(selection.location)
                let end = mapOffset(NSMaxRange(selection))
                textView.attributedText = text
                restoreSelection(NSRange(location: start, length: max(0, end - start)), in: textView)
            }
            let bounded = String(text.string.prefix(500))
            if text.string.count > 500 {
                let boundedSelection = textView.selectedRange
                textView.text = bounded
                restoreSelection(boundedSelection, in: textView)
                parent.onError("Text can contain up to 500 characters.")
            }
            parent.text = bounded
        }

        func textPasteConfigurationSupporting(_ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting, transform item: any UITextPasteItem) {
            let provider = item.itemProvider
            guard let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                item.setDefaultResult()
                return
            }
            item.setNoResult()
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
                let result: Result<Data, Error> = Result {
                    guard let url else { throw error ?? EditorError.invalidImage }
                    return try StoryStickerFile.read(url)
                }
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case let .success(data): self.parent.onSticker(data)
                    case let .failure(error): self.parent.onError(error.localizedDescription)
                    }
                }
            }
        }
    }
}

@MainActor
final class StoryTextInputHandle {
    weak var textView: UITextView?
    weak var coordinator: StoryTextInput.Coordinator?

    func focus() {
        textView?.becomeFirstResponder()
    }

    func blur() {
        textView?.resignFirstResponder()
    }

    func committedText() -> String? {
        guard let textView else { return nil }
        textView.unmarkText()
        coordinator?.textViewDidChange(textView)
        return String(textView.text.prefix(500))
    }
}

struct StoryStickerFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            StoryStickerFile(data: try read(received.file))
        }
    }
    static func read(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 20 * 1_024 * 1_024 else { throw EditorError.imageTooLarge }
        return try Data(contentsOf: url)
    }
}
