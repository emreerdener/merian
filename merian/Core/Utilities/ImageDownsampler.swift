import Foundation
import CoreGraphics
import ImageIO

// MARK: - System Hardware Image Downsampler
/// Safely downsamples massive native 12MP photos natively within CoreGraphics bounds preventing SwiftUI from triggering Out of Memory (OOM) JetSam crashes natively.
public actor ImageDownsampler {
    
    public static let shared = ImageDownsampler()
    
    // MARK: - Disk Bound Operations
    /// Downsamples a physical file payload natively into a constrained CGImage bound
    public func downsample(url: URL, maxSize: CGFloat) -> CGImage? {
        return autoreleasepool {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]
        
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
            return cgImage
        }
    }
    
    // MARK: - Memory Bound Operations
    /// Downsamples raw binary bytes natively into a constrained CGImage bound
    public func downsample(data: Data, maxSize: CGFloat) -> CGImage? {
        return autoreleasepool {
            let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ]
        
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
            return cgImage
        }
    }
}
