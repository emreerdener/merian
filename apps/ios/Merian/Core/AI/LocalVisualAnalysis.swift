import CoreGraphics
import Foundation
import UIKit
import Vision

// MARK: - Vision subject classification

struct VisionClassificationCandidate: Sendable, Equatable {
    let identifier: String
    let confidence: Float
}

struct VisionSubjectClassification: Sendable, Equatable {
    let category: LocalSubjectCategory?
    let candidates: [VisionClassificationCandidate]
}

protocol VisionSubjectClassifying: Sendable {
    func classify(
        image: ImageDownsampler.SendableImage
    ) async throws -> VisionSubjectClassification
}

struct AppleVisionSubjectClassifier: VisionSubjectClassifying {
    func classify(
        image: ImageDownsampler.SendableImage
    ) async throws -> VisionSubjectClassification {
        let classificationTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: image.cgImage, options: [:])
            try autoreleasepool {
                try handler.perform([request])
            }
            try Task.checkCancellation()

            let candidates = (request.results ?? []).prefix(5).map {
                VisionClassificationCandidate(
                    identifier: $0.identifier,
                    confidence: $0.confidence
                )
            }
            return VisionSubjectClassificationResolver.resolve(candidates: candidates)
        }
        return try await withTaskCancellationHandler {
            try await classificationTask.value
        } onCancel: {
            classificationTask.cancel()
        }
    }
}

enum VisionSubjectClassificationResolver {
    static func resolve(
        candidates: [VisionClassificationCandidate],
        confidenceThreshold: Float = MerianConfig.visionConfidenceThreshold,
        marginThreshold: Float = MerianConfig.visionMarginThreshold
    ) -> VisionSubjectClassification {
        guard let top = candidates.first,
              top.confidence >= confidenceThreshold else {
            return VisionSubjectClassification(category: nil, candidates: candidates)
        }
        if candidates.count >= 2,
           top.confidence - candidates[1].confidence < marginThreshold {
            return VisionSubjectClassification(category: nil, candidates: candidates)
        }
        return VisionSubjectClassification(
            category: LocalSubjectCategory(identifier: top.identifier),
            candidates: candidates
        )
    }
}

enum LocalSubjectCategory: String, CaseIterable, Sendable {
    case avian
    case arthropod
    case arachnid
    case fungal
    case floweringPlant
    case tree
    case succulent
    case botanical
    case reptile
    case amphibian
    case fish
    case mammal

    init?(identifier: String) {
        let tokens = Set(
            identifier.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        for category in Self.allCases where category.identifierTerms.contains(where: {
            Self.matches(identifierTerm: $0, tokens: tokens)
        }) {
            self = category
            return
        }
        return nil
    }

    var phraseSeries: [String] {
        switch self {
        case .avian:
            return [
                "Avian form visible",
                "Examining feather pattern",
                "Studying bill shape",
                "Tracing wing proportions",
                "Comparing tail outline"
            ]
        case .arthropod:
            return [
                "Arthropod form visible",
                "Examining wing veins",
                "Studying body segments",
                "Tracing appendage shape",
                "Comparing limb proportions"
            ]
        case .arachnid:
            return [
                "Arachnid form visible",
                "Examining leg arrangement",
                "Studying body segments",
                "Tracing surface markings",
                "Comparing body proportions"
            ]
        case .fungal:
            return [
                "Fungal form visible",
                "Examining cap shape",
                "Studying gill structure",
                "Tracing surface texture",
                "Comparing underside pattern"
            ]
        case .floweringPlant:
            return [
                "Flowering form visible",
                "Examining petal layout",
                "Studying flower structure",
                "Tracing bloom pattern",
                "Reviewing center markings"
            ]
        case .tree:
            return [
                "Tree form visible",
                "Examining bark texture",
                "Studying leaf shape",
                "Tracing branch structure",
                "Comparing canopy outline"
            ]
        case .succulent:
            return [
                "Succulent form visible",
                "Examining spine pattern",
                "Studying stem shape",
                "Tracing surface texture",
                "Reviewing rib contours"
            ]
        case .botanical:
            return [
                "Plant form visible",
                "Examining leaf shape",
                "Studying vein pattern",
                "Tracing growth structure",
                "Comparing edge contours"
            ]
        case .reptile:
            return [
                "Reptile form visible",
                "Examining scale pattern",
                "Studying body shape",
                "Tracing dorsal markings",
                "Reviewing head profile"
            ]
        case .amphibian:
            return [
                "Amphibian form visible",
                "Examining skin texture",
                "Studying body shape",
                "Tracing surface markings",
                "Comparing limb proportions"
            ]
        case .fish:
            return [
                "Aquatic form visible",
                "Examining fin shape",
                "Studying body proportions",
                "Tracing side markings",
                "Reviewing tail profile"
            ]
        case .mammal:
            return [
                "Mammal form visible",
                "Examining coat pattern",
                "Studying body proportions",
                "Tracing facial markings",
                "Reviewing limb proportions"
            ]
        }
    }

    private var identifierTerms: [String] {
        switch self {
        case .avian:
            return ["bird", "avian", "raptor", "songbird", "waterfowl", "owl"]
        case .arthropod:
            return [
                "insect", "arthropod", "butterfly", "moth", "bee", "beetle",
                "fly", "ant", "wasp", "dragonfly", "cricket", "grasshopper"
            ]
        case .arachnid:
            return ["spider", "arachnid", "scorpion", "tick", "mite"]
        case .fungal:
            return ["mushroom", "fungal", "fungi", "fungus", "lichen"]
        case .floweringPlant:
            return ["flower", "flowering", "blossom", "bloom"]
        case .tree:
            return ["tree", "conifer", "palm"]
        case .succulent:
            return ["cactus", "cacti", "cactaceae", "succulent"]
        case .botanical:
            return [
                "plant", "leaf", "leaves", "vegetation", "shrub", "grass",
                "fern", "moss", "algae", "vine"
            ]
        case .reptile:
            return ["reptile", "snake", "lizard", "turtle", "crocodile", "gecko"]
        case .amphibian:
            return ["amphibian", "frog", "toad", "salamander", "newt", "caecilian"]
        case .fish:
            return ["fish", "shark", "ray", "eel", "salmon", "trout"]
        case .mammal:
            return [
                "mammal", "dog", "cat", "deer", "fox", "bear", "rabbit",
                "squirrel", "raccoon", "rodent", "primate"
            ]
        }
    }

    private static func matches(
        identifierTerm: String,
        tokens: Set<String>
    ) -> Bool {
        if tokens.contains(identifierTerm)
            || tokens.contains(identifierTerm + "s")
            || tokens.contains(identifierTerm + "es") {
            return true
        }
        guard identifierTerm.hasSuffix("y") else { return false }
        return tokens.contains(String(identifierTerm.dropLast()) + "ies")
    }
}

// MARK: - Bounded local image

enum LocalVisualAnalysisImageBuilder {
    static let maximumPixelSize: CGFloat = 512

    static func makeImage(
        data: Data,
        focusRegion: NormalizedImageFocusRegion?
    ) async -> ImageDownsampler.SendableImage? {
        let imageTask = Task.detached(priority: .userInitiated) {
            () -> ImageDownsampler.SendableImage? in
            guard !Task.isCancelled,
                  let image = ImageDownsampler.downsampledSendableImage(
                      data: data,
                      maxSize: maximumPixelSize
                  ) else {
                return nil
            }
            guard let focusRegion,
                  let cropRect = pixelCropRect(
                      focusRegion: focusRegion,
                      pixelWidth: image.cgImage.width,
                      pixelHeight: image.cgImage.height
                  ),
                  let croppedImage = image.cgImage.cropping(to: cropRect) else {
                return image
            }
            return ImageDownsampler.SendableImage(cgImage: croppedImage)
        }
        return await withTaskCancellationHandler {
            await imageTask.value
        } onCancel: {
            imageTask.cancel()
        }
    }

    static func pixelCropRect(
        focusRegion: NormalizedImageFocusRegion,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGRect? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let normalized = focusRegion.rect.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        guard !normalized.isNull, !normalized.isEmpty else { return nil }

        let rawRect = CGRect(
            x: normalized.minX * CGFloat(pixelWidth),
            y: normalized.minY * CGFloat(pixelHeight),
            width: normalized.width * CGFloat(pixelWidth),
            height: normalized.height * CGFloat(pixelHeight)
        )
        let integralRect = CGRect(
            x: floor(rawRect.minX),
            y: floor(rawRect.minY),
            width: ceil(rawRect.maxX) - floor(rawRect.minX),
            height: ceil(rawRect.maxY) - floor(rawRect.minY)
        ).intersection(bounds)
        return integralRect.isEmpty ? nil : integralRect
    }
}

// MARK: - Deterministic image-derived traits

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

    private static func extractCues(from image: CGImage) -> [FoundationVisualCue] {
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
            pixels.append(PixelSample(
                red: red,
                green: green,
                blue: blue,
                luminance: 0.2126 * red + 0.7152 * green + 0.0722 * blue
            ))
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

    private static func colorIntensityDetail(for pixels: [PixelSample]) -> String {
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

// MARK: - Foundation visual cue contract

enum FoundationVisualTraitKind: String, CaseIterable, Sendable {
    case colorPattern
    case colorIntensity
    case tone
    case contrast
    case shape
    case surfaceTexture
    case structure
    case arrangement
    case proportion
    case marking

    var pillAction: String {
        switch self {
        case .colorPattern: "Analyzing"
        case .colorIntensity: "Reviewing"
        case .tone: "Observing"
        case .contrast: "Assessing"
        case .shape: "Examining"
        case .surfaceTexture: "Noting"
        case .structure: "Inspecting"
        case .arrangement: "Following"
        case .proportion: "Comparing"
        case .marking: "Reviewing"
        }
    }
}

struct FoundationVisualCue: Sendable, Equatable {
    let kind: FoundationVisualTraitKind
    let detail: String

    var pillText: String {
        "\(kind.pillAction) \(detail)"
    }
}

/// A cumulative stream snapshot. Providers may send kind and detail separately;
/// the engine only publishes a cue after `isComplete` and both fields are present.
struct FoundationVisualCueSnapshot: Sendable, Equatable {
    let index: Int
    let kind: FoundationVisualTraitKind?
    let detail: String?
    let isComplete: Bool
}

struct FoundationVisualCueRequest: Sendable {
    static let maximumCueCount = 3

    let image: ImageDownsampler.SendableImage
    let broadCategory: LocalSubjectCategory?
    let forbiddenIdentityTerms: Set<String>
}

protocol FoundationVisualCueProviding: Sendable {
    /// Stable iOS 27 implementations must use `SystemLanguageModel.default`,
    /// return nil when its on-device model is unavailable or not ready, and
    /// must never opt into a Private Cloud Compute fallback.
    func cueSnapshots(
        for request: FoundationVisualCueRequest
    ) async throws -> AsyncThrowingStream<FoundationVisualCueSnapshot, Error>?
}

/// Xcode 26.6 has no stable multimodal Foundation Models API. AppDI owns this
/// no-op provider until the release toolchain moves to stable Xcode 27.
struct UnavailableFoundationVisualCueProvider: FoundationVisualCueProviding {
    func cueSnapshots(
        for _: FoundationVisualCueRequest
    ) async throws -> AsyncThrowingStream<FoundationVisualCueSnapshot, Error>? {
        nil
    }
}

struct FoundationVisualCueBuffer {
    private struct PartialCue {
        var kind: FoundationVisualTraitKind?
        var detail: String?
        var isComplete = false
    }

    private var partialCues: [Int: PartialCue] = [:]
    private var completedIndices: Set<Int> = []

    mutating func consume(_ snapshot: FoundationVisualCueSnapshot) -> FoundationVisualCue? {
        guard snapshot.index >= 0,
              snapshot.index < FoundationVisualCueRequest.maximumCueCount,
              !completedIndices.contains(snapshot.index) else {
            return nil
        }

        var partial = partialCues[snapshot.index] ?? PartialCue()
        partial.kind = snapshot.kind ?? partial.kind
        partial.detail = snapshot.detail ?? partial.detail
        partial.isComplete = partial.isComplete || snapshot.isComplete
        partialCues[snapshot.index] = partial

        guard partial.isComplete,
              let kind = partial.kind,
              let detail = partial.detail else {
            return nil
        }
        completedIndices.insert(snapshot.index)
        partialCues.removeValue(forKey: snapshot.index)
        return FoundationVisualCue(kind: kind, detail: detail)
    }
}

enum FoundationVisualCueValidator {
    static let maximumRenderedCharacterCount = 36

    private static let bannedTerms: Set<String> = [
        "amphibian", "animal", "arachnid", "arthropod", "avian", "bird",
        "botanical", "candidate", "candidates", "cactus", "certain",
        "certainly", "checking", "class", "complete", "completed",
        "confidence", "confident", "confirmed", "confirming", "database",
        "definite", "definitely", "family", "fish", "flower", "fungal",
        "fungus", "gemini", "genus", "identified", "identifies", "identify",
        "identification", "insect", "like", "likely", "lookup", "mammal", "match",
        "matched", "matches", "matching", "maybe", "mushroom", "order",
        "plant", "possible", "possibly", "probably", "record", "records",
        "reptile", "result", "search", "searching", "species", "spider",
        "succulent", "taxon", "taxonomy", "tree"
    ]

    static func validatedCue(
        _ cue: FoundationVisualCue,
        forbiddenIdentityTerms: Set<String>,
        existingPhrases: Set<String> = []
    ) -> FoundationVisualCue? {
        let detail = cue.detail
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let words = detail.split(separator: " ")
        guard (2...5).contains(words.count),
              detail.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar)
                      || scalar == " "
                      || scalar == "-"
              }),
              !detail.lowercased().contains("-like") else {
            return nil
        }

        let normalizedTokens = lexicalTokens(in: detail)
        guard bannedTerms.isDisjoint(with: normalizedTokens),
              forbiddenIdentityTerms.isDisjoint(with: normalizedTokens) else {
            return nil
        }

        let validated = FoundationVisualCue(kind: cue.kind, detail: detail)
        guard validated.pillText.count + 3 <= maximumRenderedCharacterCount,
              !existingPhrases.contains(validated.pillText.lowercased()) else {
            return nil
        }
        return validated
    }

    static func identityTerms(
        from candidates: [VisionClassificationCandidate]
    ) -> Set<String> {
        let stopWords: Set<String> = [
            "and", "for", "from", "of", "or", "the", "to", "with"
        ]
        return Set(candidates.flatMap {
            lexicalTokens(in: $0.identifier).filter {
                $0.count >= 2 && !stopWords.contains($0)
            }
        })
    }

    private static func lexicalTokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

struct FoundationVisualCueRuntimeState: Sendable, Equatable {
    let isApplicationActive: Bool
    let isLowPowerModeEnabled: Bool
    let thermalState: ProcessInfo.ThermalState

    var isEligible: Bool {
        guard isApplicationActive, !isLowPowerModeEnabled else { return false }
        switch thermalState {
        case .serious, .critical:
            return false
        case .nominal, .fair:
            return true
        @unknown default:
            return false
        }
    }

    @MainActor
    static var current: Self {
        Self(
            isApplicationActive: UIApplication.shared.applicationState == .active,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }
}

protocol FoundationVisualCueEligibilityChecking: Sendable {
    @MainActor
    func isEligibleForVisualCues() -> Bool
}

struct SystemFoundationCueEligibility: FoundationVisualCueEligibilityChecking {
    @MainActor
    func isEligibleForVisualCues() -> Bool {
        FoundationVisualCueRuntimeState.current.isEligible
    }
}

// MARK: - Phrase coordination

protocol ScanningPhraseSleeping: Sendable {
    func sleepUntilNextPhrase() async throws
}

struct ContinuousScanningPhraseSleeper: ScanningPhraseSleeping {
    func sleepUntilNextPhrase() async throws {
        try await Task.sleep(
            nanoseconds: MerianConfig.scanningPhaseRotationIntervalNs
        )
    }
}

struct ScanningPhraseCoordinator {
    enum Specificity: Int, Sendable {
        case generic
        case vision
        case localTrait
        case foundation
    }

    static let genericPhrases = [
        "Analyzing subject",
        "Examining visible form",
        "Studying surface patterns",
        "Tracing structural details",
        "Reviewing visible contours"
    ]

    private(set) var specificity: Specificity = .generic
    private(set) var currentPhrase = genericPhrases[0]
    private(set) var phrases = genericPhrases
    private(set) var nextIndex = 1
    private(set) var shownPhrases: Set<String> = [
        genericPhrases[0].lowercased()
    ]
    private(set) var acceptedLocalTraitPhrases: Set<String> = []
    private(set) var acceptedLocalTraitDetails: Set<String> = []
    private(set) var acceptedFoundationPhrases: Set<String> = []
    private(set) var acceptedFoundationDetails: Set<String> = []

    mutating func reset() -> String {
        specificity = .generic
        phrases = Self.genericPhrases
        currentPhrase = Self.genericPhrases[0]
        nextIndex = 1
        shownPhrases = [currentPhrase.lowercased()]
        acceptedLocalTraitPhrases = []
        acceptedLocalTraitDetails = []
        acceptedFoundationPhrases = []
        acceptedFoundationDetails = []
        return currentPhrase
    }

    /// Vision completion is an immediate context handoff. The next automatic
    /// transition still waits for the shared phrase clock.
    mutating func promote(to category: LocalSubjectCategory) -> String {
        guard specificity == .generic else {
            return currentPhrase
        }
        specificity = .vision
        phrases = category.phraseSeries
        nextIndex = 0
        return publishNextPhraseInCycle() ?? currentPhrase
    }

    mutating func acceptLocalTraitCue(_ cue: FoundationVisualCue) -> Bool {
        let normalized = cue.pillText.lowercased()
        let normalizedDetail = cue.detail.lowercased()
        guard specificity.rawValue <= Specificity.localTrait.rawValue,
              !shownPhrases.contains(normalized),
              !acceptedLocalTraitPhrases.contains(normalized),
              !acceptedLocalTraitDetails.contains(normalizedDetail),
              acceptedLocalTraitPhrases.count < LocalVisualTraitCuePolicy.maximumCueCount else {
            return false
        }
        acceptedLocalTraitPhrases.insert(normalized)
        acceptedLocalTraitDetails.insert(normalizedDetail)
        if specificity != .localTrait {
            specificity = .localTrait
            phrases = []
            nextIndex = 0
        }
        phrases.append(cue.pillText)
        return true
    }

    mutating func acceptFoundationCue(_ cue: FoundationVisualCue) -> Bool {
        let normalized = cue.pillText.lowercased()
        let normalizedDetail = cue.detail.lowercased()
        guard !shownPhrases.contains(normalized),
              !acceptedFoundationPhrases.contains(normalized),
              !acceptedFoundationDetails.contains(normalizedDetail),
              acceptedFoundationPhrases.count < FoundationVisualCueRequest.maximumCueCount else {
            return false
        }
        acceptedFoundationPhrases.insert(normalized)
        acceptedFoundationDetails.insert(normalizedDetail)
        if specificity != .foundation {
            specificity = .foundation
            phrases = []
            nextIndex = 0
        }
        phrases.append(cue.pillText)
        return true
    }

    mutating func nextPhrase() -> String? {
        publishNextPhraseInCycle()
    }

    /// Captures the active deck for a same-scan presentation handoff. The
    /// currently visible phrase stays first, unseen phrases follow in cadence
    /// order, and already-seen phrases are deferred until every available
    /// option has been exhausted.
    var handoffPhraseDeck: [String] {
        guard !phrases.isEmpty else { return [currentPhrase] }

        let orderedCandidates = phrases.indices.map { offset in
            phrases[(nextIndex + offset) % phrases.count]
        }
        let currentKey = currentPhrase.lowercased()
        let unseen = orderedCandidates.filter {
            let key = $0.lowercased()
            return key != currentKey && !shownPhrases.contains(key)
        }
        let previouslySeen = orderedCandidates.filter {
            let key = $0.lowercased()
            return key != currentKey && shownPhrases.contains(key)
        }

        var result = [currentPhrase]
        var included = Set([currentKey])
        for phrase in unseen + previouslySeen
            where included.insert(phrase.lowercased()).inserted {
            result.append(phrase)
        }
        return result
    }

    /// Walks every currently available phrase before wrapping to the beginning.
    /// A one-phrase deck holds steady because reassigning the same label would
    /// not create a meaningful UI transition.
    private mutating func publishNextPhraseInCycle() -> String? {
        guard !phrases.isEmpty else { return nil }
        var examinedCount = 0
        while examinedCount < phrases.count {
            if nextIndex >= phrases.count {
                nextIndex = 0
            }
            let candidate = phrases[nextIndex]
            nextIndex += 1
            examinedCount += 1
            let normalized = candidate.lowercased()
            guard candidate != currentPhrase else { continue }
            shownPhrases.insert(normalized)
            currentPhrase = candidate
            return candidate
        }
        return nil
    }
}
