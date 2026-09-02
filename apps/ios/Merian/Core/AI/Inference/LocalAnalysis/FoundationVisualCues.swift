import Foundation
import UIKit

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
/// consumers publish a cue only after `isComplete` and both fields are present.
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

    mutating func consume(
        _ snapshot: FoundationVisualCueSnapshot
    ) -> FoundationVisualCue? {
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
        "identification", "insect", "like", "likely", "lookup", "mammal",
        "match", "matched", "matches", "matching", "maybe", "mushroom",
        "order", "plant", "possible", "possibly", "probably", "record",
        "records", "reptile", "result", "search", "searching", "species",
        "spider", "succulent", "taxon", "taxonomy", "tree"
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
        return Set(
            candidates.flatMap {
                lexicalTokens(in: $0.identifier).filter {
                    $0.count >= 2 && !stopWords.contains($0)
                }
            }
        )
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
            isApplicationActive:
                UIApplication.shared.applicationState == .active,
            isLowPowerModeEnabled:
                ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }
}

protocol FoundationVisualCueEligibilityChecking: Sendable {
    @MainActor
    func isEligibleForVisualCues() -> Bool
}

struct SystemFoundationCueEligibility:
    FoundationVisualCueEligibilityChecking {
    @MainActor
    func isEligibleForVisualCues() -> Bool {
        FoundationVisualCueRuntimeState.current.isEligible
    }
}
