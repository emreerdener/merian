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
                "Tracing wing proportions"
            ]
        case .arthropod:
            return [
                "Arthropod form visible",
                "Examining wing veins",
                "Studying body segments",
                "Tracing appendage shape"
            ]
        case .arachnid:
            return [
                "Arachnid form visible",
                "Examining leg arrangement",
                "Studying body segments",
                "Tracing surface markings"
            ]
        case .fungal:
            return [
                "Fungal form visible",
                "Examining cap shape",
                "Studying gill structure",
                "Tracing surface texture"
            ]
        case .floweringPlant:
            return [
                "Flowering form visible",
                "Examining petal layout",
                "Studying flower structure",
                "Tracing bloom pattern"
            ]
        case .tree:
            return [
                "Tree form visible",
                "Examining bark texture",
                "Studying leaf shape",
                "Tracing branch structure"
            ]
        case .succulent:
            return [
                "Succulent form visible",
                "Examining spine pattern",
                "Studying stem shape",
                "Tracing surface texture"
            ]
        case .botanical:
            return [
                "Plant form visible",
                "Examining leaf shape",
                "Studying vein pattern",
                "Tracing growth structure"
            ]
        case .reptile:
            return [
                "Reptile form visible",
                "Examining scale pattern",
                "Studying body shape",
                "Tracing dorsal markings"
            ]
        case .amphibian:
            return [
                "Amphibian form visible",
                "Examining skin texture",
                "Studying body shape",
                "Tracing surface markings"
            ]
        case .fish:
            return [
                "Aquatic form visible",
                "Examining fin shape",
                "Studying body proportions",
                "Tracing side markings"
            ]
        case .mammal:
            return [
                "Mammal form visible",
                "Examining coat pattern",
                "Studying body proportions",
                "Tracing facial markings"
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

// MARK: - Foundation visual cue contract

enum FoundationVisualTraitKind: String, CaseIterable, Sendable {
    case colorPattern
    case shape
    case surfaceTexture
    case structure
    case arrangement
    case proportion
    case marking

    var pillPrefix: String {
        switch self {
        case .colorPattern: "Color"
        case .shape: "Shape"
        case .surfaceTexture: "Surface"
        case .structure: "Structure"
        case .arrangement: "Pattern"
        case .proportion: "Proportion"
        case .marking: "Marking"
        }
    }
}

struct FoundationVisualCue: Sendable, Equatable {
    let kind: FoundationVisualTraitKind
    let detail: String

    var pillText: String {
        "\(kind.pillPrefix): \(detail)"
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
        case foundation
    }

    static let genericPhrases = [
        "Analyzing subject",
        "Examining visible form",
        "Studying surface patterns",
        "Tracing structural details"
    ]

    private(set) var specificity: Specificity = .generic
    private(set) var currentPhrase = genericPhrases[0]
    private(set) var phrases = genericPhrases
    private(set) var nextIndex = 1
    private(set) var acceptedFoundationPhrases: Set<String> = []
    private(set) var acceptedFoundationDetails: Set<String> = []

    mutating func reset() -> String {
        specificity = .generic
        phrases = Self.genericPhrases
        currentPhrase = Self.genericPhrases[0]
        nextIndex = 1
        acceptedFoundationPhrases = []
        acceptedFoundationDetails = []
        return currentPhrase
    }

    /// Vision completion is an immediate context handoff. The next automatic
    /// transition still waits for the shared phrase clock.
    mutating func promote(to category: LocalSubjectCategory) -> String {
        guard specificity.rawValue <= Specificity.vision.rawValue else {
            return currentPhrase
        }
        specificity = .vision
        phrases = category.phraseSeries
        currentPhrase = phrases[0]
        nextIndex = phrases.count > 1 ? 1 : 0
        return currentPhrase
    }

    mutating func acceptFoundationCue(_ cue: FoundationVisualCue) -> Bool {
        let normalized = cue.pillText.lowercased()
        let normalizedDetail = cue.detail.lowercased()
        guard !acceptedFoundationPhrases.contains(normalized),
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
        guard !phrases.isEmpty else { return nil }
        if phrases.count == 1, phrases[0] == currentPhrase {
            return nil
        }

        var candidate = phrases[nextIndex % phrases.count]
        nextIndex = (nextIndex + 1) % phrases.count
        if candidate == currentPhrase, phrases.count > 1 {
            candidate = phrases[nextIndex % phrases.count]
            nextIndex = (nextIndex + 1) % phrases.count
        }
        guard candidate != currentPhrase else { return nil }
        currentPhrase = candidate
        return candidate
    }
}
