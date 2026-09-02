import CoreGraphics
import Foundation

protocol LocalVisualTraitExtracting: Sendable {
    /// Implementations must observe task cancellation and return promptly.
    func extractCues(
        from image: ImageDownsampler.SendableImage
    ) async -> [FoundationVisualCue]
}

enum LocalVisualTraitCuePolicy {
    /// Five cues cover the normal 11-second analysis window at the shared
    /// 2.3-second cadence before a deck needs to wrap.
    static let maximumCueCount = 5
}

/// Produces directly observable, image-specific cues on the current toolchain.
/// This is deliberately deterministic: it samples a tiny RGBA derivative and
/// never infers identity, taxonomy, confidence, or a candidate label.
struct AppleImageVisualTraitExtractor: LocalVisualTraitExtracting {
    private static let sampleDimension = 32

    private enum PaletteTone: String, CaseIterable {
        case dark
        case gray
        case light
        case red
        case orange
        case yellow
        case green
        case teal
        case blue
        case purple
        case pink
        case brown

        var rank: Int {
            Self.allCases.firstIndex(of: self) ?? 0
        }
    }

    private struct PixelSample {
        let red: Double
        let green: Double
        let blue: Double
        let luminance: Double
    }

    private struct SampledImage {
        let pixels: [PixelSample]
        let width: Int
        let height: Int
    }

    func extractCues(
        from image: ImageDownsampler.SendableImage
    ) async -> [FoundationVisualCue] {
        let extractionTask = Task.detached(priority: .utility) {
            Self.extractCues(from: image.cgImage)
        }
        return await withTaskCancellationHandler {
            await extractionTask.value
        } onCancel: {
            extractionTask.cancel()
        }
    }

    private static func extractCues(
        from image: CGImage
    ) -> [FoundationVisualCue] {
        guard !Task.isCancelled,
              let sampled = sampledPixels(from: image),
              !sampled.pixels.isEmpty else {
            return []
        }

        let pixels = sampled.pixels
        let paletteCue = FoundationVisualCue(
            kind: .colorPattern,
            detail: paletteDetail(for: pixels)
        )
        let colorIntensityCue = FoundationVisualCue(
            kind: .colorIntensity,
            detail: colorIntensityDetail(for: pixels)
        )
        let toneCue = FoundationVisualCue(
            kind: .tone,
            detail: toneDetail(for: pixels)
        )
        let contrastCue = FoundationVisualCue(
            kind: .contrast,
            detail: contrastDetail(for: pixels)
        )
        let surfaceCue = FoundationVisualCue(
            kind: .surfaceTexture,
            detail: surfaceDetail(
                for: pixels,
                width: sampled.width,
                height: sampled.height
            )
        )
        return [
            paletteCue,
            colorIntensityCue,
            toneCue,
            contrastCue,
            surfaceCue
        ]
    }

    private static func sampledPixels(from image: CGImage) -> SampledImage? {
        let width = min(sampleDimension, image.width)
        let height = min(sampleDimension, image.height)
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(width),
                height: CGFloat(height)
            )
        )
        guard !Task.isCancelled else { return nil }

        var pixels: [PixelSample] = []
        pixels.reserveCapacity(width * height)
        for offset in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha >= 0.10 else { continue }
            let red = min(1, Double(bytes[offset]) / 255 / alpha)
            let green = min(1, Double(bytes[offset + 1]) / 255 / alpha)
            let blue = min(1, Double(bytes[offset + 2]) / 255 / alpha)
            pixels.append(
                PixelSample(
                    red: red,
                    green: green,
                    blue: blue,
                    luminance: 0.2126 * red + 0.7152 * green
                        + 0.0722 * blue
                )
            )
        }
        return SampledImage(pixels: pixels, width: width, height: height)
    }

    private static func paletteDetail(for pixels: [PixelSample]) -> String {
        var counts: [PaletteTone: Int] = [:]
        for pixel in pixels {
            counts[paletteTone(for: pixel), default: 0] += 1
        }
        let ranked = PaletteTone.allCases
            .map { ($0, counts[$0, default: 0]) }
            .filter { $0.1 > 0 }
            .sorted { left, right in
                if left.1 == right.1 {
                    return left.0.rank < right.0.rank
                }
                return left.1 > right.1
            }
        guard let first = ranked.first else { return "mostly gray colors" }
        let firstShare = Double(first.1) / Double(pixels.count)
        guard ranked.count > 1 else {
            return "mostly \(first.0.rawValue) colors"
        }
        let second = ranked[1]
        let secondShare = Double(second.1) / Double(pixels.count)
        if firstShare >= 0.72 || secondShare < 0.12 {
            return "mostly \(first.0.rawValue) colors"
        }
        return "\(first.0.rawValue) and \(second.0.rawValue) colors"
    }

    private static func paletteTone(for pixel: PixelSample) -> PaletteTone {
        let maximum = max(pixel.red, max(pixel.green, pixel.blue))
        let minimum = min(pixel.red, min(pixel.green, pixel.blue))
        let delta = maximum - minimum
        let saturation = maximum == 0 ? 0 : delta / maximum

        if maximum < 0.18 { return .dark }
        if saturation < 0.16 {
            if pixel.luminance > 0.78 { return .light }
            return .gray
        }

        var hue: Double
        if maximum == pixel.red {
            hue = 60 * ((pixel.green - pixel.blue) / delta)
        } else if maximum == pixel.green {
            hue = 60 * (2 + (pixel.blue - pixel.red) / delta)
        } else {
            hue = 60 * (4 + (pixel.red - pixel.green) / delta)
        }
        if hue < 0 { hue += 360 }

        if (20..<55).contains(hue), maximum < 0.65 {
            return .brown
        }
        switch hue {
        case 0..<20, 345..<360: return .red
        case 20..<45: return .orange
        case 45..<70: return .yellow
        case 70..<165: return .green
        case 165..<195: return .teal
        case 195..<255: return .blue
        case 255..<290: return .purple
        default: return .pink
        }
    }

    private static func contrastDetail(for pixels: [PixelSample]) -> String {
        let mean = pixels.reduce(0) { $0 + $1.luminance }
            / Double(pixels.count)
        let variance = pixels.reduce(0) {
            let difference = $1.luminance - mean
            return $0 + difference * difference
        } / Double(pixels.count)
        switch sqrt(variance) {
        case 0..<0.10: return "subtle light changes"
        case 0.22...: return "stark lighting"
        default: return "varied lighting"
        }
    }

    private static func colorIntensityDetail(
        for pixels: [PixelSample]
    ) -> String {
        let saturations = pixels.map { pixel in
            let maximum = max(pixel.red, max(pixel.green, pixel.blue))
            let minimum = min(pixel.red, min(pixel.green, pixel.blue))
            return maximum == 0 ? 0 : (maximum - minimum) / maximum
        }
        let mutedCount = saturations.reduce(0) { count, saturation in
            count + (saturation < 0.18 ? 1 : 0)
        }
        let vividCount = saturations.reduce(0) { count, saturation in
            count + (saturation >= 0.48 ? 1 : 0)
        }
        let mutedShare = Double(mutedCount) / Double(saturations.count)
        let vividShare = Double(vividCount) / Double(saturations.count)

        if mutedShare >= 0.60 { return "mostly muted colors" }
        if vividShare >= 0.60 { return "mostly vivid colors" }
        if mutedShare >= 0.20, vividShare >= 0.20 {
            return "muted and vivid colors"
        }
        return "softly colored areas"
    }

    private static func toneDetail(for pixels: [PixelSample]) -> String {
        let meanLuminance = pixels.reduce(0) { $0 + $1.luminance }
            / Double(pixels.count)
        if meanLuminance < 0.32 { return "mostly shadowed areas" }
        if meanLuminance >= 0.68 { return "mostly bright areas" }

        let variance = pixels.reduce(0.0) { result, pixel in
            let difference = pixel.luminance - meanLuminance
            return result + difference * difference
        } / Double(pixels.count)
        if sqrt(variance) < 0.10 {
            return "evenly lit areas"
        }
        return "light and shadow areas"
    }

    private static func surfaceDetail(
        for pixels: [PixelSample],
        width: Int,
        height: Int
    ) -> String {
        guard pixels.count == width * height else {
            return "smooth and detailed areas"
        }
        var totalDifference = 0.0
        var comparisonCount = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if x + 1 < width {
                    totalDifference += pixelDifference(
                        pixels[index],
                        pixels[index + 1]
                    )
                    comparisonCount += 1
                }
                if y + 1 < height {
                    totalDifference += pixelDifference(
                        pixels[index],
                        pixels[index + width]
                    )
                    comparisonCount += 1
                }
            }
        }
        guard comparisonCount > 0 else { return "broad smooth areas" }
        switch totalDifference / Double(comparisonCount) {
        case 0..<0.07: return "broad smooth areas"
        case 0.17...: return "many fine edges"
        default: return "smooth and detailed areas"
        }
    }

    private static func pixelDifference(
        _ first: PixelSample,
        _ second: PixelSample
    ) -> Double {
        let luminanceDifference = abs(first.luminance - second.luminance)
        let channelDifference = max(
            abs(first.red - second.red),
            max(
                abs(first.green - second.green),
                abs(first.blue - second.blue)
            )
        )
        return 0.7 * luminanceDifference + 0.3 * channelDifference
    }
}
