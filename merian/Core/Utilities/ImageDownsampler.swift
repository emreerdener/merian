import Foundation
import CoreGraphics
import ImageIO

/// Safely downsamples massive native 12MP photos natively within CoreGraphics bounds preventing SwiftUI from triggering Out of Memory (OOM) JetSam crashes natively.
public struct ImageDownsampler {
    
    /// Downsamples a physical file payload natively into a constrained CGImage bound
    public static func downsample(url: URL, maxSize: CGFloat) -> CGImage? {
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
    
    /// Downsamples raw binary bytes natively into a constrained CGImage bound
    public static func downsample(data: Data, maxSize: CGFloat) -> CGImage? {
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
