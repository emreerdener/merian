import Foundation
import CoreGraphics
import ImageIO

/// Downsamples large photos using ImageIO thumbnailing to avoid OOM pressure.
/// All operations are `nonisolated` and safe to call from any concurrency context.
public actor ImageDownsampler {

    public static let shared = ImageDownsampler()

    private static let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary

    private nonisolated func thumbnailOptions(maxSize: CGFloat) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ] as CFDictionary
    }

    /// Downsamples an image file at `url` to fit within `maxSize` pixels on the longest edge.
    public nonisolated func downsample(url: URL, maxSize: CGFloat) -> CGImage? {
        autoreleasepool {
            let options = thumbnailOptions(maxSize: maxSize)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, Self.sourceOptions),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            return image
        }
    }

    /// Downsamples an image from raw `data` to fit within `maxSize` pixels on the longest edge.
    public nonisolated func downsample(data: Data, maxSize: CGFloat) -> CGImage? {
        autoreleasepool {
            let options = thumbnailOptions(maxSize: maxSize)
            guard let source = CGImageSourceCreateWithData(data as CFData, Self.sourceOptions),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            return image
        }
    }
}
