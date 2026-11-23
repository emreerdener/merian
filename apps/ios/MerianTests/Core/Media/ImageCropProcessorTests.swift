import ImageIO
@testable import Merian
import Testing
import UIKit

@MainActor
@Suite("Image crop rotation")
struct ImageCropProcessorTests {
    @Test func sourceSelectionMatchesIntegralCropAcrossOrientations() async throws {
        let source = try #require(makeImage(size: CGSize(width: 241, height: 163)).cgImage)
        let orientations: [UIImage.Orientation] = [.up, .down, .left, .right,
            .upMirrored, .downMirrored, .leftMirrored, .rightMirrored]
        for orientation in orientations {
            let image = UIImage(cgImage: source, scale: 1, orientation: orientation)
            for turns in 0..<4 {
                let mapping = try #require(ImageCropProcessor.cropMapping(image: image, displaySize: 97,
                    scale: 1.73, offset: CGSize(width: 10.25, height: -7.75), quarterTurns: turns))
                #expect(mapping.cropPixels == mapping.cropPixels.integral)
                let expected = NormalizedImageFocusRegion(x: 0.17, y: 0.23, width: 0.31, height: 0.29, source: .userSelection)
                let selected = try #require(mapping.sourceSelection(fromFocus: expected))
                let actual = try #require(mapping.focus(fromSourceSelection: selected))
                for (lhs, rhs) in zip([actual.x, actual.y, actual.width, actual.height],
                                      [expected.x, expected.y, expected.width, expected.height]) {
                    #expect(abs(lhs - rhs) < 1e-12)
                }
                let bytes = await ImageCropProcessor.generateCrop(image: image, displaySize: 97,
                    scale: 1.73, currentScale: 1, offset: CGSize(width: 10.25, height: -7.75),
                    currentOffset: .zero, quarterTurns: turns, maxPixelSize: nil, encoding: .jpeg)
                let decoded = try #require(ImageDownsampler.downsample(data: bytes, maxSize: 1024))
                let swapped = [.left, .right, .leftMirrored, .rightMirrored].contains(mapping.targetOrientation)
                #expect(decoded.width == Int(swapped ? mapping.cropPixels.height : mapping.cropPixels.width))
                #expect(decoded.height == Int(swapped ? mapping.cropPixels.width : mapping.cropPixels.height))
                #expect(mapping.focus(fromSourceSelection: CGRect(x: 0, y: 0, width: 1, height: 1)) == nil)
                #expect(LocalVisualAnalysisImageBuilder.pixelCropRect(focusRegion: actual,
                    pixelWidth: decoded.width, pixelHeight: decoded.height)
                    == LocalVisualAnalysisImageBuilder.pixelCropRect(focusRegion: expected,
                        pixelWidth: decoded.width, pixelHeight: decoded.height))
            }
        }
    }

    @Test(arguments: [0, 1, 2, 3])
    func invalidCropNeverFallsBackToFullSource(turns: Int) async throws {
        let image = makeImage(size: CGSize(width: 240, height: 160))
        let result = await ImageCropProcessor.generateCrop(image: image, displaySize: 96,
            scale: 1, currentScale: 1, offset: CGSize(width: -100_000, height: -100_000),
            currentOffset: .zero, quarterTurns: turns, maxPixelSize: 96)
        #expect(result.isEmpty)
    }

    @Test func explicitJPEGPreservesCropGeometryAndSource() async throws {
        let image = makeImage(size: CGSize(width: 240, height: 160))
        let original = try #require(image.cgImage)
        let direct = try #require(ImageCropProcessor.encode(original, maxPixelSize: 96, encoding: .jpeg))
        let crop = await ImageCropProcessor.generateCrop(image: image, displaySize: 96,
            scale: 1.75, currentScale: 1, offset: CGSize(width: 11, height: -7),
            currentOffset: .zero, quarterTurns: 1, maxPixelSize: 96, encoding: .jpeg)
        for data in [direct, crop] {
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
            let decoded = try #require(ImageDownsampler.downsample(data: data, maxSize: 96))
            #expect(max(decoded.width, decoded.height) <= 96)
        }
        #expect(image.cgImage === original && original.width == 240 && original.height == 160)
        let decoded = try #require(ImageDownsampler.downsample(data: crop, maxSize: 96))
        #expect(abs(decoded.width - decoded.height) <= 1)
    }

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
