import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Downsamples large photos using ImageIO thumbnailing to avoid OOM pressure.
/// All operations are `nonisolated` and safe to call from any concurrency context.
public enum ImageDownsampler {

    public struct SendableImage: @unchecked Sendable {
        public let cgImage: CGImage

        init(cgImage: CGImage) {
            self.cgImage = cgImage
        }
    }

    private static let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary

    private static func thumbnailOptions(maxSize: CGFloat) -> CFDictionary {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize
        ] as CFDictionary
    }

    /// Composites `image` through an opaque CGContext to strip any alpha channel.
    ///
    /// Camera frames decoded by `CGImageSourceCreateThumbnailAtIndex` inherit the source
    /// pixel format, which is commonly `AlphaPremulLast`. JPEG and WebP encoders log a
    /// warning when they encounter alpha-bearing inputs ("is trying to save an opaque image
    /// with 'AlphaPremulLast'"). Drawing into a `noneSkipLast` context strips the channel
    /// without any external library dependency and without visible quality change.
    private static func stripAlpha(from image: CGImage) -> CGImage {
        let alphaInfo = image.alphaInfo
        guard alphaInfo != .none,
              alphaInfo != .noneSkipLast,
              alphaInfo != .noneSkipFirst else {
            return image  // Already opaque — nothing to do
        }
        return autoreleasepool {
            guard let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return image }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return context.makeImage() ?? image
        }
    }

    /// Downsamples an image file at `url` to fit within `maxSize` pixels on the longest edge.
    public static func downsample(url: URL, maxSize: CGFloat, stripAlpha channelStripping: Bool = true) -> CGImage? {
        autoreleasepool {
            let options = thumbnailOptions(maxSize: maxSize)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, Self.sourceOptions),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            return channelStripping ? stripAlpha(from: image) : image
        }
    }

    /// Returns a bounded `UIImage` preview without ever decoding the full source raster.
    public static func downsampledUIImage(url: URL, maxSize: CGFloat, stripAlpha channelStripping: Bool = true) -> UIImage? {
        guard let image = downsample(url: url, maxSize: maxSize, stripAlpha: channelStripping) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// Returns a bounded, sendable CoreGraphics preview for detached image-loading tasks.
    public static func downsampledSendableImage(url: URL, maxSize: CGFloat, stripAlpha channelStripping: Bool = true) -> SendableImage? {
        guard let image = downsample(url: url, maxSize: maxSize, stripAlpha: channelStripping) else {
            return nil
        }
        return SendableImage(cgImage: image)
    }

    /// Downsamples an image from raw `data` to fit within `maxSize` pixels on the longest edge.
    public static func downsample(data: Data, maxSize: CGFloat, stripAlpha channelStripping: Bool = true) -> CGImage? {
        autoreleasepool {
            let options = thumbnailOptions(maxSize: maxSize)
            guard let source = CGImageSourceCreateWithData(data as CFData, Self.sourceOptions),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            return channelStripping ? stripAlpha(from: image) : image
        }
    }

    /// Returns a bounded `UIImage` preview from encoded bytes without decoding the full source raster.
    public static func downsampledUIImage(data: Data, maxSize: CGFloat, stripAlpha channelStripping: Bool = true) -> UIImage? {
        guard let image = downsample(data: data, maxSize: maxSize, stripAlpha: channelStripping) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// Returns a bounded, sendable CoreGraphics preview from encoded bytes.
    public static func downsampledSendableImage(data: Data, maxSize: CGFloat, stripAlpha channelStripping: Bool = true) -> SendableImage? {
        guard let image = downsample(data: data, maxSize: maxSize, stripAlpha: channelStripping) else {
            return nil
        }
        return SendableImage(cgImage: image)
    }
}
