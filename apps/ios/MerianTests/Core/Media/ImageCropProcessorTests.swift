@testable import Merian
import Testing
import UIKit

@MainActor
@Suite("Image crop rotation")
struct ImageCropProcessorTests {
    @Test func rotationsPreservePixelsAndComposeWithoutCopies() throws {
        let image = makeImage(size: CGSize(width: 240, height: 160))
        let source = try #require(image.cgImage)
        let right = ImageCropProcessor.rotatedImage(image, quarterTurns: 1)
        #expect(right.cgImage === source)
        #expect(right.size == CGSize(width: 160, height: 240))
        #expect(ImageCropProcessor.rotatedImage(right, quarterTurns: -1).imageOrientation == .up)
        #expect(ImageCropProcessor.rotatedImage(image, quarterTurns: 4).imageOrientation == .up)
        let offset = CGSize(width: 17, height: -23)
        let rotated = ImageCropProcessor.rotatedOffset(offset, quarterTurns: 1)
        #expect(rotated == CGSize(width: 23, height: 17))
        #expect(ImageCropProcessor.rotatedOffset(rotated, quarterTurns: -1) == offset)
        #expect(ImageCropProcessor.rotatedOffset(offset, quarterTurns: 4) == offset)
    }

    @Test func exportedCropMatchesUIKitPreviewForEveryOrientation() async throws {
        let orientations: [UIImage.Orientation] = [
            .up, .right, .down, .left,
            .upMirrored, .rightMirrored, .downMirrored, .leftMirrored
        ]
        for size in [CGSize(width: 240, height: 160), CGSize(width: 160, height: 240)] {
            let source = try #require(makeImage(size: size).cgImage)
            for orientation in orientations {
                let image = UIImage(cgImage: source, scale: 1, orientation: orientation)
                for turns in 0..<4 {
                    for zoom: CGFloat in [1, 1.75] {
                        // Keep the same selected area as it turns, including an off-center crop.
                        let offset = ImageCropProcessor.rotatedOffset(
                            zoom == 1 ? .zero : CGSize(width: 11, height: -7),
                            quarterTurns: turns
                        )
                        let data = await ImageCropProcessor.generateCrop(
                            image: image, displaySize: 96, scale: zoom, currentScale: 1,
                            offset: offset, currentOffset: .zero, quarterTurns: turns,
                            maxPixelSize: 96
                        )
                        let decoded = try #require(ImageDownsampler.downsample(data: data, maxSize: 96))
                        #expect(abs(decoded.width - decoded.height) <= 1)
                        let expected = referenceCrop(image, turns: turns, zoom: zoom, offset: offset)
                        let actualPixels = try pixels(UIImage(cgImage: decoded))
                        let expectedPixels = try pixels(expected)
                        // Sample away from borders; lossy encoding permits a small color tolerance.
                        for y in stride(from: 12, to: 90, by: 17) {
                            for x in stride(from: 12, to: 90, by: 17) {
                                let index = (y * 96 + x) * 4
                                for channel in 0..<3 {
                                    let difference = abs(Int(actualPixels[index + channel]) - Int(expectedPixels[index + channel]))
                                    #expect(difference < 30, "orientation=\(orientation.rawValue), turns=\(turns), zoom=\(zoom)")
                                }
                                #expect(actualPixels[index + 3] == 255)
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func repeatedConfirmationUsesOriginalSource() async throws {
        let image = makeImage(size: CGSize(width: 240, height: 160))
        var original = IdentifiableImage(image: image)
        original.lastCropQuarterTurns = 1
        original.lastCropScale = 1.75
        original.lastCropOffset = CGSize(width: 7, height: 11)
        func confirm(_ item: IdentifiableImage, limit: Int) async -> Data {
            await ImageCropProcessor.generateCrop(
                image: item.image, displaySize: 96, scale: item.lastCropScale,
                currentScale: 1, offset: item.lastCropOffset, currentOffset: .zero,
                quarterTurns: item.lastCropQuarterTurns, maxPixelSize: limit
            )
        }
        let first = await confirm(original, limit: 96)
        let staged = StagedImage(compressedData: first, displayData: first, uiImage: image, original: original)
        let reopened = await confirm(staged.original, limit: 96)
        #expect(first == reopened)
        let display = await confirm(staged.original, limit: 192)
        let inferenceImage = try #require(ImageDownsampler.downsample(data: first, maxSize: 96))
        let displayImage = try #require(ImageDownsampler.downsample(data: display, maxSize: 96))
        let inferencePixels = try pixels(UIImage(cgImage: inferenceImage))
        let displayPixels = try pixels(UIImage(cgImage: displayImage))
        for index in stride(from: 0, to: inferencePixels.count, by: 4) {
            #expect(abs(Int(inferencePixels[index]) - Int(displayPixels[index])) < 30)
        }
    }

    private func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // An asymmetric continuous color field makes axis swaps and mirrors observable.
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    UIColor(
                        red: CGFloat(x) / size.width,
                        green: CGFloat(y) / size.height,
                        blue: 0.2, alpha: 1
                    ).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private func referenceCrop(_ image: UIImage, turns: Int, zoom: CGFloat, offset: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { context in
            let factor = max(96 / image.size.width, 96 / image.size.height) * zoom
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            context.cgContext.translateBy(x: 48 + offset.width, y: 48 + offset.height)
            context.cgContext.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }

    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 96 * 96 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: 96, height: 96, bitsPerComponent: 8,
                bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        return bytes
    }
}
