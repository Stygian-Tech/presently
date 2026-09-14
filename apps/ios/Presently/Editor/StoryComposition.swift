import Foundation
import ImageIO
import UIKit

struct StoryComposition: Codable, Equatable {
    static let currentVersion = 1
    var version = currentVersion
    var layers: [StoryLayer] = []

    var fitsAssetBudget: Bool {
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

    func encoded() throws -> Data {
        guard fitsAssetBudget else { throw EditorError.imageTooLarge }
        return try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data?) throws -> Self {
        guard let data else { return Self() }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == currentVersion, value.layers.count <= 30,
              value.layers.allSatisfy(\.isValid), value.fitsAssetBudget else { throw EditorError.invalidDraft }
        return value
    }
}

struct StoryLayer: Codable, Identifiable, Equatable {
    enum Style: String, Codable, CaseIterable { case bold, classic, mono }
    enum Alignment: String, Codable, CaseIterable { case left, center, right }
    var id = UUID()
    var text: String = ""
    var isEmoji: Bool = false
    var stickerPNG: Data?
    var style: Style = .bold
    var color: String = "white"
    var alignment: Alignment = .center
    var background = false
    // Position and width are relative to the upright photo, independent of its viewport.
    var x: Double = 0.5
    var y: Double = 0.5
    var width: Double = 0.65
    var rotation: Double = 0

    var isValid: Bool {
        x.isFinite && y.isFinite && width.isFinite && rotation.isFinite &&
        (0...1).contains(x) && (0...1).contains(y) && (0.08...1.5).contains(width) &&
        text.count <= 500 && (stickerPNG?.count ?? 0) <= 8 * 1_024 * 1_024
    }
}

enum EditorError: LocalizedError {
    case invalidImage, animatedSticker, invalidDraft, imageTooLarge, tooManyLayers
    var errorDescription: String? {
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
enum StoryRenderer {
    static let colors: [(String, UIColor)] = [
        ("white", .white), ("black", .black), ("yellow", .systemYellow),
        ("pink", .systemPink), ("blue", .systemBlue), ("green", .systemGreen)
    ]

    static func uprightImage(_ data: Data, maximumDimension: Int = 2_048, sticker: Bool = false) throws -> UIImage {
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

    static func layerImage(_ layer: StoryLayer) -> UIImage {
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
        }
        let paragraph = NSMutableParagraphStyle()
        switch layer.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        paragraph.lineBreakMode = .byWordWrapping
        let color = colors.first { $0.0 == layer.color }?.1 ?? .white
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ]
        let string = NSAttributedString(string: layer.text, attributes: attributes)
        let content = string.boundingRect(with: CGSize(width: 700, height: 50_000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        // Fixed text box gives alignment a meaningful width and identical line wrapping everywhere.
        let size = CGSize(width: 748, height: max(100, ceil(content.height) + 32))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rasterScale = min(1, 1_024 / size.height)
        let rasterSize = CGSize(width: size.width * rasterScale, height: size.height * rasterScale)
        return UIGraphicsImageRenderer(size: rasterSize, format: format).image { context in
            context.cgContext.scaleBy(x: rasterScale, y: rasterScale)
            if layer.background {
                (layer.color == "black" ? UIColor.white : UIColor.black).withAlphaComponent(0.8).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18).fill()
            }
            string.draw(with: CGRect(x: 24, y: 16, width: 700, height: size.height - 32), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
    }

    static func layerSize(_ layer: StoryLayer, image: UIImage, photoSize: CGSize) -> CGSize {
        let width = photoSize.width * layer.width
        return CGSize(width: width, height: width * image.size.height / image.size.width)
    }

    static func drawLayer(_ layer: StoryLayer, image: UIImage, photoRect: CGRect, context: CGContext) {
        let size = layerSize(layer, image: image, photoSize: photoRect.size)
        context.saveGState()
        context.translateBy(x: photoRect.minX + photoRect.width * layer.x, y: photoRect.minY + photoRect.height * layer.y)
        context.rotate(by: layer.rotation)
        image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
    }

    static func render(photo: UIImage, composition: StoryComposition) -> UIImage {
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

    static func jpeg(photo: UIImage, composition: StoryComposition) throws -> Data {
        let rendered = render(photo: photo, composition: composition)
        for quality in [0.9, 0.75, 0.6] {
            if let data = rendered.jpegData(compressionQuality: quality), data.count <= FlashesStoryContract.maximumImageBytes { return data }
        }
        throw EditorError.imageTooLarge
    }

    static func photoRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}
