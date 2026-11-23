import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct ImageCropProcessor {
    nonisolated static func normalizedQuarterTurns(_ turns: Int) -> Int {
        (turns % 4 + 4) % 4
    }

    /// UIKit's orientation wrapper shares the original pixels; rotation does not
    /// allocate or repeatedly encode a full-size bitmap.
    nonisolated static func rotatedImage(_ image: UIImage, quarterTurns: Int) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        var orientation = image.imageOrientation
        for _ in 0..<normalizedQuarterTurns(quarterTurns) {
            switch orientation {
            case .up: orientation = .right
            case .right: orientation = .down
            case .down: orientation = .left
            case .left: orientation = .up
            case .upMirrored: orientation = .rightMirrored
            case .rightMirrored: orientation = .downMirrored
            case .downMirrored: orientation = .leftMirrored
            case .leftMirrored: orientation = .upMirrored
            @unknown default: orientation = .right
            }
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: orientation)
    }

    nonisolated static func rotatedOffset(_ offset: CGSize, quarterTurns: Int) -> CGSize {
        switch normalizedQuarterTurns(quarterTurns) {
        case 1: return CGSize(width: -offset.height, height: offset.width)
        case 2: return CGSize(width: -offset.width, height: -offset.height)
        case 3: return CGSize(width: offset.height, height: -offset.width)
        default: return offset
        }
    }

    private static func cgOrientation(
        from orientation: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private static let supportedDestinationTypes: Set<String> = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers()
            as? [String] ?? []
        return Set(identifiers)
    }()

    private static let destinationTypePreferences: [String] = {
        var types: [String] = []
        if supportedDestinationTypes.contains(UTType.webP.identifier) {
            types.append(UTType.webP.identifier)
        }
        types.append(UTType.jpeg.identifier)
        return types
    }()

    private static func makeImageDestination(
        _ renderData: NSMutableData,
        encoding: ImagePreparationPolicy.Encoding
    ) -> CGImageDestination? {
        let types = encoding == .jpeg ? [UTType.jpeg.identifier] : destinationTypePreferences
        for type in types {
            if let destination = CGImageDestinationCreateWithData(
                renderData as CFMutableData,
                type as CFString,
                1,
                nil
            ) {
                return destination
            }
        }
        return nil
    }

    /// Defaults to WebP when ImageIO supports it, otherwise JPEG. An explicit
    /// JPEG request never falls back to a different format.
    nonisolated static func encode(
        _ cgImage: CGImage,
        quality: Double = ImagePreparationPolicy.compressionQuality,
        orientation: CGImagePropertyOrientation? = nil,
        maxPixelSize: Int? = nil,
        encoding: ImagePreparationPolicy.Encoding = .preferred
    ) -> Data? {
        autoreleasepool {
            let renderData = NSMutableData()
            guard let destination = makeImageDestination(renderData, encoding: encoding) else {
                return nil
            }
            var options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            if let orientation {
                options[kCGImagePropertyOrientation] = orientation.rawValue
            }
            if let maxPixelSize {
                options[kCGImageDestinationImageMaxPixelSize] = maxPixelSize
            }
            CGImageDestinationAddImage(
                destination,
                cgImage,
                options as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else { return nil }
            return Data(renderData)
        }
    }

    nonisolated static func generateCrop(
        image: UIImage,
        displaySize: CGFloat,
        scale: CGFloat,
        currentScale: CGFloat,
        offset: CGSize,
        currentOffset: CGSize,
        quarterTurns: Int = 0,
        maxPixelSize: Int? = Int(
            ImagePreparationPolicy.maximumInferenceDimension
        ),
        encoding: ImagePreparationPolicy.Encoding = .preferred
    ) async -> Data {
        guard let mapping = cropMapping(image: image, displaySize: displaySize,
            scale: scale * currentScale,
            offset: CGSize(width: offset.width + currentOffset.width, height: offset.height + currentOffset.height),
            quarterTurns: quarterTurns), let sourceCGImage = image.cgImage else { return Data() }
        let processedBytes: Data? = autoreleasepool {
            let cropRect = mapping.cropPixels
            // A failed edit must leave the previous staged artifact intact.
            // Returning the full source would submit a different framing.
            guard !cropRect.isEmpty, !cropRect.isNull,
                  let croppedImage = sourceCGImage.cropping(to: cropRect) else { return nil }
            return encode(
                croppedImage,
                orientation: cgOrientation(from: mapping.targetOrientation),
                maxPixelSize: maxPixelSize,
                encoding: encoding
            )
        }

        return processedBytes ?? Data()
    }

    /// Geometry for both encoded pixels and submitted subject selection.
    nonisolated static func cropMapping(image: UIImage, displaySize: CGFloat, scale: CGFloat,
                                        offset: CGSize, quarterTurns: Int) -> ImageCropMapping? {
        guard displaySize > 0, displaySize.isFinite, scale >= 1, scale.isFinite,
              offset.width.isFinite, offset.height.isFinite, let sourceCGImage = image.cgImage else { return nil }
        let rotated = rotatedImage(image, quarterTurns: quarterTurns)
        let imageSize = rotated.size
        let targetOrientation = rotated.imageOrientation
        let finalScale = scale
        let finalOffset = offset
        let sourceWidth = imageSize.width
        let sourceHeight = imageSize.height
        let imageRatio = sourceWidth / sourceHeight
        let renderedWidth = imageRatio > 1
            ? displaySize * imageRatio
            : displaySize
        let imageScale = sourceWidth / renderedWidth

        let horizontalOffset = -finalOffset.width
            / finalScale * imageScale
        let verticalOffset = -finalOffset.height
            / finalScale * imageScale
        let visibleWidth = displaySize / finalScale * imageScale
        let visibleHeight = displaySize / finalScale * imageScale
        let cropX = (sourceWidth - visibleWidth) / 2 + horizontalOffset
        let cropY = (sourceHeight - visibleHeight) / 2 + verticalOffset

        let normalizedX = max(
            0,
            min(1, cropX / sourceWidth)
        )
        let normalizedY = max(
            0,
            min(1, cropY / sourceHeight)
        )
        let normalizedWidth = min(
            1 - normalizedX,
            max(0, visibleWidth / sourceWidth)
        )
        let normalizedHeight = min(
            1 - normalizedY,
            max(0, visibleHeight / sourceHeight)
        )

        let raw = ImageCropMapping.rawRect(fromUpright: CGRect(
            x: normalizedX, y: normalizedY, width: normalizedWidth, height: normalizedHeight
        ), orientation: targetOrientation)
        let cropRect = CGRect(x: raw.minX * CGFloat(sourceCGImage.width),
                              y: raw.minY * CGFloat(sourceCGImage.height),
                              width: raw.width * CGFloat(sourceCGImage.width),
                              height: raw.height * CGFloat(sourceCGImage.height))
        // CGImage crops on integral pixels. Both the exported artifact and
        // its focus transform must use this exact same rounded rectangle.
        let pixels = cropRect.integral.intersection(CGRect(x: 0, y: 0,
            width: sourceCGImage.width, height: sourceCGImage.height))
        guard !pixels.isEmpty, !pixels.isNull else { return nil }
        return ImageCropMapping(sourcePixelSize: CGSize(width: sourceCGImage.width, height: sourceCGImage.height),
            sourceOrientation: image.imageOrientation, targetOrientation: targetOrientation, cropPixels: pixels)
    }

    /// Convert immutable normalized shutter framing to the crop editor's current
    /// point geometry. Opening/cancelling the editor does not change that recipe.
    nonisolated static func initialSquareCropOffset(imageSize: CGSize, displaySize: CGFloat,
                                                    verticalCenterFraction: CGFloat) -> CGSize? {
        let width = imageSize.width, height = imageSize.height
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              displaySize.isFinite, displaySize > 0, verticalCenterFraction.isFinite,
              (0...1).contains(verticalCenterFraction) else { return nil }
        let side = min(width, height)
        let cropY = max(0, min(height * verticalCenterFraction - side / 2, height - side))
        let y = ((height - side) / 2 - cropY) / side * displaySize
        guard y.isFinite else { return nil }
        return CGSize(width: 0, height: y)
    }

    /// Crops a downsampled CGImage to the largest centered square, biasing the vertical
    /// center toward `verticalCenterFraction` (0 = top, 0.5 = geometric center, 1 = bottom).
    /// Pass the fraction measured from the on-screen composing zone so the crop reflects
    /// where the user actually framed their subject, not the dead center of the sensor.
    nonisolated static func squareCrop(
        _ cgImage: CGImage,
        verticalCenterFraction: CGFloat
    ) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)

        let cropX = (width - side) / 2
        let cropY = max(
            0,
            min(
                height * verticalCenterFraction - side / 2,
                height - side
            )
        )

        return cgImage.cropping(to: CGRect(
            x: cropX,
            y: cropY,
            width: side,
            height: side
        ))
    }
}
