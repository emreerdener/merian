import SwiftUI
import UniformTypeIdentifiers

// MARK: - Native Image Cropping Engine
struct ImageCropProcessor {

    // MARK: - Private Helpers

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up:           return .up
        case .down:         return .down
        case .left:         return .left
        case .right:        return .right
        case .upMirrored:   return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:   return .up
        }
    }

    private static let supportedDestinationTypes: Set<String> = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
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

    /// Attempts WebP only when ImageIO advertises a writer for it; otherwise uses JPEG.
    private static func makeImageDestination(_ renderData: NSMutableData) -> CGImageDestination? {
        for type in destinationTypePreferences {
            if let destination = CGImageDestinationCreateWithData(renderData as CFMutableData, type as CFString, 1, nil) {
                return destination
            }
        }
        return nil
    }

    /// Encodes a `CGImage` to WebP (JPEG fallback) inside an `autoreleasepool`, returning the
    /// compressed bytes. Consolidates the repeated CGImageDestination → NSMutableData pattern
    /// used across `generateCrop`, `generateAutoCenterCrop`, and `Capture.swift`.
    ///
    /// - Parameters:
    ///   - cgImage: Source image to encode.
    ///   - quality: Lossy compression quality 0.0–1.0. Defaults to `MerianConfig.imageCompressionQuality`.
    ///   - orientation: EXIF orientation to embed. Pass `nil` when the transform is already baked.
    ///   - maxPixelSize: Optional longest-edge cap applied during encoding (nil = no limit).
    /// - Returns: Encoded `Data`, or `nil` if the destination or finalize step fails.
    static nonisolated func encode(
        _ cgImage: CGImage,
        quality: Double = MerianConfig.imageCompressionQuality,
        orientation: CGImagePropertyOrientation? = nil,
        maxPixelSize: Int? = nil
    ) -> Data? {
        autoreleasepool {
            let renderData = NSMutableData()
            guard let destination = makeImageDestination(renderData) else { return nil }
            var options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            if let orientation { options[kCGImagePropertyOrientation] = orientation.rawValue }
            if let maxPixelSize { options[kCGImageDestinationImageMaxPixelSize] = maxPixelSize }
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return Data(renderData)
        }
    }
    
    // MARK: - Async Generation Boundary
    nonisolated static func generateCrop(
        image: UIImage,
        displaySize: CGFloat,
        scale: CGFloat,
        currentScale: CGFloat,
        offset: CGSize,
        currentOffset: CGSize,
        maxPixelSize: Int? = 1024
    ) async -> Data {
        
        // MARK: - UI Bounds Math
        let finalScale = scale * currentScale
        let finalOffset = CGSize(
            width: offset.width + currentOffset.width,
            height: offset.height + currentOffset.height
        )
        
        // MARK: - Sendable Isolation Wrappers
        // Capture properties securely for detached thread to prevent MainActor UI block
        let targetSize = image.size
        let targetCGImage = image.cgImage
        let targetOrientation = image.imageOrientation
        
        // MARK: - Detached Hardware Execution
        let processedBytes: Data? = autoreleasepool {
                let W = targetSize.width
                let H = targetSize.height
                
                guard let cgImg = targetCGImage else {
                    return nil
                }
                
                // MARK: 1. SwiftUI Coordinate Algebra
                let imageRatio = W / H
                let renderedWidth = imageRatio > 1 ? displaySize * imageRatio : displaySize
                let imageScale = W / renderedWidth
                
                // Map the SwiftUI view transforms mathematically backward to original image points
                let dxOffsetOriginal = -finalOffset.width / finalScale * imageScale
                let dyOffsetOriginal = -finalOffset.height / finalScale * imageScale
                
                let visibleWidthOriginal = displaySize / finalScale * imageScale
                let visibleHeightOriginal = displaySize / finalScale * imageScale
                
                let cropX = (W - visibleWidthOriginal) / 2.0 + dxOffsetOriginal
                let cropY = (H - visibleHeightOriginal) / 2.0 + dyOffsetOriginal
                
                let rawUx = cropX / W
                let rawUy = cropY / H
                let rawUw = visibleWidthOriginal / W
                let rawUh = visibleHeightOriginal / H
                
                let ux = max(0.0, min(1.0, rawUx))
                let uy = max(0.0, min(1.0, rawUy))
                let uw = min(1.0 - ux, max(0.0, rawUw))
                let uh = min(1.0 - uy, max(0.0, rawUh))
                
                let cW = CGFloat(cgImg.width)
                let cH = CGFloat(cgImg.height)
                
                // MARK: 2. CoreGraphics Matrix Orientation
                // Natively flip bounds based on Apple sensor rotation (imageOrientation)
                var cropRect: CGRect
                switch targetOrientation {
                case .up:           cropRect = CGRect(x: ux * cW, y: uy * cH, width: uw * cW, height: uh * cH)
                case .down:         cropRect = CGRect(x: (1 - ux - uw) * cW, y: (1 - uy - uh) * cH, width: uw * cW, height: uh * cH)
                case .left:         cropRect = CGRect(x: (1 - uy - uh) * cW, y: ux * cH, width: uh * cW, height: uw * cH)
                case .right:        cropRect = CGRect(x: uy * cW, y: (1 - ux - uw) * cH, width: uh * cW, height: uw * cH)
                case .upMirrored:   cropRect = CGRect(x: (1 - ux - uw) * cW, y: uy * cH, width: uw * cW, height: uh * cH)
                case .downMirrored: cropRect = CGRect(x: ux * cW, y: (1 - uy - uh) * cH, width: uw * cW, height: uh * cH)
                case .leftMirrored: cropRect = CGRect(x: (1 - uy - uh) * cW, y: (1 - ux - uw) * cH, width: uh * cW, height: uw * cH)
                case .rightMirrored: cropRect = CGRect(x: uy * cW, y: ux * cH, width: uh * cW, height: uw * cH)
                @unknown default:   cropRect = CGRect(x: ux * cW, y: uy * cH, width: uw * cW, height: uh * cH)
                }
                
                // MARK: 3. CGImagePropertyOrientation Translation
                let cgOrientation = cgOrientation(from: targetOrientation)

                // MARK: 4. Native Bitmap Payload Dispatch
                // Isolate memory extraction cleanly in the background CPU pool natively
                // Fallback to original cgImg if cropping fails to ensure off-main-thread processing
                let finalCG = cgImg.cropping(to: cropRect) ?? cgImg

                return ImageCropProcessor.encode(finalCG, orientation: cgOrientation, maxPixelSize: maxPixelSize)
        }

        return processedBytes ?? Data()
    }
    
    // MARK: - Composing-Zone-Aware Square Crop
    /// Crops a downsampled CGImage to the largest centered square, biasing the vertical
    /// center toward `verticalCenterFraction` (0 = top, 0.5 = geometric center, 1 = bottom).
    /// Pass the fraction measured from the on-screen composing zone so the crop reflects
    /// where the user actually framed their subject, not the dead center of the sensor.
    nonisolated static func squareCrop(_ cgImage: CGImage, verticalCenterFraction: CGFloat) -> CGImage? {
        let cW = CGFloat(cgImage.width)
        let cH = CGFloat(cgImage.height)
        let side = min(cW, cH)

        let cropX = (cW - side) / 2.0
        let cropY = max(0, min(cH * verticalCenterFraction - side / 2.0, cH - side))

        return cgImage.cropping(to: CGRect(x: cropX, y: cropY, width: side, height: side))
    }

    // MARK: - Zero-Latency Auto-Crop Pipeline (Active Scan)
    nonisolated static func generateAutoCenterCrop(image: UIImage) async -> Data {
        // MARK: - Sendable Isolation Wrappers
        let targetCGImage = image.cgImage
        let targetOrientation = image.imageOrientation
        
        let processedBytes: Data? = autoreleasepool {
                guard let cgImg = targetCGImage else {
                    return nil
                }
                
                let cW = CGFloat(cgImg.width)
                let cH = CGFloat(cgImg.height)
                
                // Calculate 1:1 Center Square bounds based on the shortest edge to guarantee native coverage constraints natively
                let shortestSide = min(cW, cH)
                let cropX = (cW - shortestSide) / 2.0
                let cropY = (cH - shortestSide) / 2.0
                let cropRect = CGRect(x: cropX, y: cropY, width: shortestSide, height: shortestSide)
                
                // MARK: 1. CGImagePropertyOrientation Translation
                let cgOrientation = cgOrientation(from: targetOrientation)

                // MARK: 2. Native Bitmap Payload Dispatch
                let finalCG = cgImg.cropping(to: cropRect) ?? cgImg

                return ImageCropProcessor.encode(finalCG, quality: 0.7, orientation: cgOrientation, maxPixelSize: 1024)
        }

        return processedBytes ?? Data()
    }
}
