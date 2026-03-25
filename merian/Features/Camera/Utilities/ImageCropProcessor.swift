import SwiftUI
import UniformTypeIdentifiers

// MARK: - Native Image Cropping Engine
struct ImageCropProcessor {
    
    // MARK: - Async Generation Boundary
    nonisolated static func generateCrop(
        image: UIImage,
        displaySize: CGFloat,
        scale: CGFloat,
        currentScale: CGFloat,
        offset: CGSize,
        currentOffset: CGSize
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
                case .rightMirrored:cropRect = CGRect(x: uy * cW, y: ux * cH, width: uh * cW, height: uw * cH)
                @unknown default:   cropRect = CGRect(x: ux * cW, y: uy * cH, width: uw * cW, height: uh * cH)
                }
                
                // MARK: 3. CGImagePropertyOrientation Translation
                // Map UIImage.Orientation directly to CGImagePropertyOrientation natively
                let cgOrientation: CGImagePropertyOrientation
                switch targetOrientation {
                case .up: cgOrientation = .up
                case .down: cgOrientation = .down
                case .left: cgOrientation = .left
                case .right: cgOrientation = .right
                case .upMirrored: cgOrientation = .upMirrored
                case .downMirrored: cgOrientation = .downMirrored
                case .leftMirrored: cgOrientation = .leftMirrored
                case .rightMirrored: cgOrientation = .rightMirrored
                @unknown default: cgOrientation = .up
                }
                
                // MARK: 4. Native Bitmap Payload Dispatch
                // Isolate memory extraction cleanly in the background CPU pool natively
                // Fallback to original cgImg if cropping fails to ensure off-main-thread processing
                let finalCG = cgImg.cropping(to: cropRect) ?? cgImg
                
                let renderData = NSMutableData()
                
                // Write the payload using native C abstractions strictly bypassing intermediate UIGraphicsImageRenderer bitmap RAM bloat routines
                guard let destination = CGImageDestinationCreateWithData(renderData as CFMutableData, UTType.webP.identifier as CFString, 1, nil) else {
                    return nil
                }

                let options: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: 0.7,
                    kCGImagePropertyOrientation: cgOrientation.rawValue,
                    kCGImageDestinationImageMaxPixelSize: 1024 // Force maximum gemini down-render dynamically
                ]
                
                CGImageDestinationAddImage(destination, finalCG, options as CFDictionary)
                
                guard CGImageDestinationFinalize(destination) else {
                    return nil
                }
                
            return Data(renderData)
        }
        
        return processedBytes ?? Data()
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
                let cgOrientation: CGImagePropertyOrientation
                switch targetOrientation {
                case .up: cgOrientation = .up
                case .down: cgOrientation = .down
                case .left: cgOrientation = .left
                case .right: cgOrientation = .right
                case .upMirrored: cgOrientation = .upMirrored
                case .downMirrored: cgOrientation = .downMirrored
                case .leftMirrored: cgOrientation = .leftMirrored
                case .rightMirrored: cgOrientation = .rightMirrored
                @unknown default: cgOrientation = .up
                }
                
                // MARK: 2. Native Bitmap Payload Dispatch
                let finalCG = cgImg.cropping(to: cropRect) ?? cgImg
                
                let renderData = NSMutableData()
                
                // Write the payload using native C abstractions strictly bypassing intermediate UIGraphicsImageRenderer bitmap RAM bloat routines
                guard let destination = CGImageDestinationCreateWithData(renderData as CFMutableData, UTType.webP.identifier as CFString, 1, nil) else {
                    return nil
                }

                let options: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: 0.7,
                    kCGImagePropertyOrientation: cgOrientation.rawValue,
                    kCGImageDestinationImageMaxPixelSize: 1024 // Force maximum gemini down-render dynamically natively guaranteeing speed
                ]
                
                CGImageDestinationAddImage(destination, finalCG, options as CFDictionary)
                
                guard CGImageDestinationFinalize(destination) else {
                    return nil
                }
                
            return Data(renderData)
        }
        
        return processedBytes ?? Data()
    }
}
