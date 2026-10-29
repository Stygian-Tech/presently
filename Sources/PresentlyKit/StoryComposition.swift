import Foundation
import ImageIO
import UIKit

public struct StoryComposition: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version = currentVersion
    public var layers: [StoryLayer] = []
    // Absent in older drafts, whose original framing must stay intact.
    public var usesStoryCrop: Bool?
    // The full-screen preview's aspect ratio, frozen at shutter time.
    public var captureViewportAspectRatio: Double?

    public init(version: Int = Self.currentVersion, layers: [StoryLayer] = [], usesStoryCrop: Bool? = nil, captureViewportAspectRatio: Double? = nil) {
        self.version = version
        self.layers = layers
        self.usesStoryCrop = usesStoryCrop
        self.captureViewportAspectRatio = captureViewportAspectRatio
    }

    public var fitsAssetBudget: Bool {
        let images = layers.compactMap(\.stickerPNG)
        guard images.reduce(0, { $0 + $1.count }) <= 8 * 1_024 * 1_024 else { return false }
        var pixels = 0
        for data in images {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 1_024, height <= 1_024 else { return false }
            pixels += width * height
        }
        return pixels <= 6 * 1_024 * 1_024
    }

    public func encoded() throws -> Data {
        guard fitsAssetBudget else { throw EditorError.imageTooLarge }
        return try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data?) throws -> Self {
        guard let data else { return Self() }
        let value = try JSONDecoder().decode(Self.self, from: data)
        if let ratio = value.captureViewportAspectRatio {
            guard ratio.isFinite, ratio > 0 else { throw EditorError.invalidDraft }
        }
        guard value.version == currentVersion, value.layers.count <= 30,
              value.layers.allSatisfy(\.isValid), value.fitsAssetBudget else { throw EditorError.invalidDraft }
        return value
    }
}

public struct StoryLayer: Codable, Identifiable, Equatable, Sendable {
    public enum Style: String, Codable, CaseIterable, Sendable {
        case bold, classic, mono, serif, rounded, boldRounded

        public var title: LocalizedStringResource {
            switch self {
            case .bold: "Bold"
            case .classic: "Classic"
            case .mono: "Monospaced"
            case .serif: "Serif"
            case .rounded: "Rounded"
            case .boldRounded: "Bold Rounded"
            }
        }
    }
    public enum Alignment: String, Codable, CaseIterable, Sendable { case left, center, right }
    public var id = UUID()
    public var text: String = ""
    public var isEmoji: Bool = false
    public var stickerPNG: Data?
    public var style: Style = .bold
    public var color: String = "white"
    public var alignment: Alignment = .center
    public var background = false
    // Position and width are relative to the upright photo, independent of its viewport.
    public var x: Double = 0.5
    public var y: Double = 0.5
    public var width: Double = 0.65
    public var rotation: Double = 0
    // Nil preserves the original wrapping width in existing drafts.
    public var textBoxWidth: Double?
    public var resolvedTextBoxWidth: Double {
        get { textBoxWidth ?? 1 }
        set { textBoxWidth = newValue }
    }

    public init(id: UUID = UUID(), text: String = "", isEmoji: Bool = false, stickerPNG: Data? = nil,
                style: Style = .bold, color: String = "white", alignment: Alignment = .center,
                background: Bool = false, x: Double = 0.5, y: Double = 0.5,
                width: Double = 0.65, rotation: Double = 0, textBoxWidth: Double? = nil) {
        self.id = id
        self.text = text
        self.isEmoji = isEmoji
        self.stickerPNG = stickerPNG
        self.style = style
        self.color = color
        self.alignment = alignment
        self.background = background
        self.x = x
        self.y = y
        self.width = width
        self.rotation = rotation
        self.textBoxWidth = textBoxWidth
    }

    public var isValid: Bool {
        x.isFinite && y.isFinite && width.isFinite && rotation.isFinite &&
        (0...1).contains(x) && (0...1).contains(y) && (0.08...1.5).contains(width) &&
        resolvedTextBoxWidth.isFinite && (0.35...1.5).contains(resolvedTextBoxWidth) &&
        text.count <= 500 && (stickerPNG?.count ?? 0) <= 8 * 1_024 * 1_024
    }
}

public enum EditorError: LocalizedError {
    case invalidImage, animatedSticker, invalidDraft, imageTooLarge, tooManyLayers
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "This image could not be opened."
        case .animatedSticker: "Choose a still image for this sticker."
        case .invalidDraft: "This draft uses an unsupported or damaged editor format."
        case .imageTooLarge: "This image is too large. Choose a smaller image."
        case .tooManyLayers: "A photo can contain up to 30 text and sticker layers."
        }
    }
}

@MainActor
public enum StoryRenderer {
    public static let storyAspectRatio: CGFloat = 9.0 / 16.0

    public static func storyCrop(_ uprightPhoto: UIImage, viewportAspectRatio: Double? = nil) throws -> UIImage {
        guard let image = uprightPhoto.cgImage else { throw EditorError.invalidImage }
        // Whole 9-by-16 pixel units keep the exported aspect ratio exact.
        let cropSize = storyCropSize(
            imageSize: CGSize(width: image.width, height: image.height),
            viewportAspectRatio: viewportAspectRatio
        )
        let unit = Int(min(cropSize.width / 9, cropSize.height / 16).rounded(.down))
        guard unit > 0 else { throw EditorError.invalidImage }
        let width = unit * 9
        let height = unit * 16
        let rect = CGRect(
            x: (image.width - width) / 2, y: (image.height - height) / 2,
            width: width, height: height
        )
        guard let cropped = image.cropping(to: rect) else { throw EditorError.invalidImage }
        return UIImage(cgImage: cropped)
    }

    /// Map a centered 9:16 frame back through the preview's aspect-fill scale.
    /// Cropping the full sensor to 9:16 instead would zoom out on a tall display.
    public static func storyCropSize(imageSize: CGSize, viewportAspectRatio: Double?) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let ratio = viewportAspectRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            ?? Double(storyAspectRatio)
        let viewport = CGSize(width: ratio, height: 1)
        let previewScale = max(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let storyFrame = photoRect(
            imageSize: CGSize(width: 9, height: 16),
            bounds: CGRect(origin: .zero, size: viewport)
        )
        return CGSize(width: storyFrame.width / previewScale, height: storyFrame.height / previewScale)
    }

    public static let colors: [(String, UIColor)] = [
        ("white", .white), ("black", .black), ("yellow", .systemYellow),
        ("pink", .systemPink), ("blue", .systemBlue), ("green", .systemGreen)
    ]

    public static func textColor(_ value: String) -> UIColor {
        if let preset = colors.first(where: { $0.0 == value }) { return preset.1 }
        guard value.hasPrefix("#"), value.count == 7,
              let rgb = UInt32(value.dropFirst(), radix: 16) else { return .white }
        return UIColor(
            red: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255,
            alpha: 1
        )
    }

    public static func colorValue(_ color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return "white" }
        let components = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    public static func uprightImage(_ data: Data, maximumDimension: Int = 2_048, sticker: Bool = false) throws -> UIImage {
        guard data.count <= 20 * 1_024 * 1_024,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw EditorError.invalidImage }
        if sticker && CGImageSourceGetCount(source) > 1 { throw EditorError.animatedSticker }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw EditorError.invalidImage
        }
        return UIImage(cgImage: cgImage)
    }

    public static func layerImage(_ layer: StoryLayer) -> UIImage {
        if let data = layer.stickerPNG, let image = UIImage(data: data) { return image }
        if layer.isEmoji {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160), format: format).image { _ in
                (layer.text as NSString).draw(in: CGRect(x: 8, y: 0, width: 150, height: 160), withAttributes: [.font: UIFont.systemFont(ofSize: 132)])
            }
        }
        let font: UIFont
        switch layer.style {
        case .bold: font = .systemFont(ofSize: 64, weight: .heavy)
        case .classic: font = .systemFont(ofSize: 64, weight: .regular)
        case .mono: font = .monospacedSystemFont(ofSize: 64, weight: .semibold)
        case .serif, .rounded, .boldRounded:
            let base = UIFont.systemFont(ofSize: 64, weight: layer.style == .boldRounded ? .heavy : .medium)
            let design: UIFontDescriptor.SystemDesign = layer.style == .serif ? .serif : .rounded
            font = base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: 64) } ?? base
        }
        let paragraph = NSMutableParagraphStyle()
        switch layer.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        paragraph.lineBreakMode = .byWordWrapping
        let color = textColor(layer.color)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ]
        let string = NSAttributedString(string: layer.text, attributes: attributes)
        let textWidth = 700 * layer.resolvedTextBoxWidth
        let content = string.boundingRect(with: CGSize(width: textWidth, height: 50_000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        // Use the same wrapping width for canvas previews and exported images.
        let size = CGSize(width: textWidth + 48, height: max(100, ceil(content.height) + 32))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rasterScale = min(1, 1_024 / max(size.width, size.height))
        let rasterSize = CGSize(width: size.width * rasterScale, height: size.height * rasterScale)
        return UIGraphicsImageRenderer(size: rasterSize, format: format).image { context in
            context.cgContext.scaleBy(x: rasterScale, y: rasterScale)
            if layer.background {
                (colorValue(color) == "#000000" ? UIColor.white : UIColor.black).withAlphaComponent(0.8).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18).fill()
            }
            string.draw(with: CGRect(x: 24, y: 16, width: textWidth, height: size.height - 32), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    public static func layerSize(_ layer: StoryLayer, image: UIImage, photoSize: CGSize) -> CGSize {
        let boxScale = layer.stickerPNG == nil && !layer.isEmoji
            ? (700 * layer.resolvedTextBoxWidth + 48) / 748 : 1
        let width = photoSize.width * layer.width * boxScale
        return CGSize(width: width, height: width * image.size.height / image.size.width)
    }

    public static func drawLayer(_ layer: StoryLayer, image: UIImage, photoRect: CGRect, context: CGContext) {
        let size = layerSize(layer, image: image, photoSize: photoRect.size)
        context.saveGState()
        context.translateBy(x: photoRect.minX + photoRect.width * layer.x, y: photoRect.minY + photoRect.height * layer.y)
        context.rotate(by: layer.rotation)
        image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
    }

    public static func render(photo: UIImage, composition: StoryComposition) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: photo.size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: photo.size)
            UIColor.black.setFill()
            context.fill(rect)
            photo.draw(in: rect)
            for layer in composition.layers {
                drawLayer(layer, image: layerImage(layer), photoRect: rect, context: context.cgContext)
            }
        }
    }

    public static func jpeg(photo: UIImage, composition: StoryComposition, maximumBytes: Int = FlashesStoryContract.maximumImageBytes) throws -> Data {
        guard maximumBytes > 0 else { throw EditorError.imageTooLarge }
        let rendered = render(photo: photo, composition: composition)
        for quality in [0.9, 0.75, 0.6] {
            if let data = rendered.jpegData(compressionQuality: quality), data.count <= maximumBytes { return data }
        }
        throw EditorError.imageTooLarge
    }

    public static func photoRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}
