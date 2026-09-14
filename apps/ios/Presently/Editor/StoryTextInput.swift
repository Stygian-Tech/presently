import SwiftUI
import UIKit
import UniformTypeIdentifiers

// UIKit exposes keyboard stickers and adaptive image glyphs on iOS 18 while
// retaining native selection, dictation and the text editing menu on iOS 17.
struct StoryTextInput: UIViewRepresentable {
    @Binding var text: String
    var handle: StoryTextInputHandle? = nil
    let onSticker: (Data) -> Void
    let onError: (String) -> Void

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
        handle?.textView = view
        handle?.coordinator = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(view, modelText: text)
    }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: StoryTextInput
        init(_ parent: StoryTextInput) { self.parent = parent }

        func synchronize(_ textView: UITextView, modelText: String) {
            // SwiftUI may deliver an older binding snapshot between native keystrokes.
            // While editing, UIKit owns the text and its marked/selected ranges.
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
            // Do not normalize or publish an IME's provisional text. Committing it
            // produces another delegate change with no marked range.
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

    /// A toolbar action can run before SwiftUI consumes the final delegate update.
    /// Read the native editor synchronously, committing any IME marked text first.
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
