import Foundation

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
              acceptedLocalTraitPhrases.count
                < LocalVisualTraitCuePolicy.maximumCueCount else {
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
              acceptedFoundationPhrases.count
                < FoundationVisualCueRequest.maximumCueCount else {
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
