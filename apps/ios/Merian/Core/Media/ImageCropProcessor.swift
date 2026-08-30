import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct ImageCropProcessor {
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
        _ renderData: NSMutableData
    ) -> CGImageDestination? {
        for type in destinationTypePreferences {
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

    /// Encodes WebP when ImageIO advertises support, otherwise JPEG.
    nonisolated static func encode(
        _ cgImage: CGImage,
        quality: Double = MerianConfig.imageCompressionQuality,
        orientation: CGImagePropertyOrientation? = nil,
        maxPixelSize: Int? = nil
    ) -> Data? {
        autoreleasepool {
            let renderData = NSMutableData()
            guard let destination = makeImageDestination(renderData) else {
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
        maxPixelSize: Int? = 1024
    ) async -> Data {
        let finalScale = scale * currentScale
        let finalOffset = CGSize(
            width: offset.width + currentOffset.width,
            height: offset.height + currentOffset.height
        )

        let imageSize = image.size
        let sourceCGImage = image.cgImage
        let targetOrientation = image.imageOrientation

        let processedBytes: Data? = autoreleasepool {
            guard let sourceCGImage else { return nil }

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

            let pixelWidth = CGFloat(sourceCGImage.width)
            let pixelHeight = CGFloat(sourceCGImage.height)
            let cropRect: CGRect
            switch targetOrientation {
            case .up:
                cropRect = CGRect(
                    x: normalizedX * pixelWidth,
                    y: normalizedY * pixelHeight,
                    width: normalizedWidth * pixelWidth,
                    height: normalizedHeight * pixelHeight
                )
            case .down:
                cropRect = CGRect(
                    x: (1 - normalizedX - normalizedWidth) * pixelWidth,
                    y: (1 - normalizedY - normalizedHeight) * pixelHeight,
                    width: normalizedWidth * pixelWidth,
                    height: normalizedHeight * pixelHeight
                )
            case .left:
                cropRect = CGRect(
                    x: (1 - normalizedY - normalizedHeight) * pixelWidth,
                    y: normalizedX * pixelHeight,
                    width: normalizedHeight * pixelWidth,
                    height: normalizedWidth * pixelHeight
                )
            case .right:
                cropRect = CGRect(
                    x: normalizedY * pixelWidth,
                    y: (1 - normalizedX - normalizedWidth) * pixelHeight,
                    width: normalizedHeight * pixelWidth,
                    height: normalizedWidth * pixelHeight
                )
            case .upMirrored:
                cropRect = CGRect(
                    x: (1 - normalizedX - normalizedWidth) * pixelWidth,
                    y: normalizedY * pixelHeight,
                    width: normalizedWidth * pixelWidth,
                    height: normalizedHeight * pixelHeight
                )
            case .downMirrored:
                cropRect = CGRect(
                    x: normalizedX * pixelWidth,
                    y: (1 - normalizedY - normalizedHeight) * pixelHeight,
                    width: normalizedWidth * pixelWidth,
                    height: normalizedHeight * pixelHeight
                )
            case .leftMirrored:
                cropRect = CGRect(
                    x: (1 - normalizedY - normalizedHeight) * pixelWidth,
                    y: (1 - normalizedX - normalizedWidth) * pixelHeight,
                    width: normalizedHeight * pixelWidth,
                    height: normalizedWidth * pixelHeight
                )
            case .rightMirrored:
                cropRect = CGRect(
                    x: normalizedY * pixelWidth,
                    y: normalizedX * pixelHeight,
                    width: normalizedHeight * pixelWidth,
                    height: normalizedWidth * pixelHeight
                )
            @unknown default:
                cropRect = CGRect(
                    x: normalizedX * pixelWidth,
                    y: normalizedY * pixelHeight,
                    width: normalizedWidth * pixelWidth,
                    height: normalizedHeight * pixelHeight
                )
            }

            let croppedImage = sourceCGImage.cropping(to: cropRect)
                ?? sourceCGImage
            return encode(
                croppedImage,
                orientation: cgOrientation(from: targetOrientation),
                maxPixelSize: maxPixelSize
            )
        }

        return processedBytes ?? Data()
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
