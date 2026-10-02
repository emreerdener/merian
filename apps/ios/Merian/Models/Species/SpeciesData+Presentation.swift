import Foundation

enum ReferenceImageVisibilityPolicy {
    static func shouldSuppress(
        isHumanSubject: Bool,
        scientificName: String
    ) -> Bool {
        if isHumanSubject { return true }

        let normalizedScientificName = scientificName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedScientificName == "felis catus"
            || normalizedScientificName == "canis lupus familiaris"
    }
}

enum HumanSubjectIdentityPolicy {
    private static let aliases: Set<String> = [
        "human",
        "humans",
        "human being",
        "person",
        "human breathing",
        "human speech",
        "human vocalisation",
        "human vocalization",
        "homo sapiens",
        "homo sapien"
    ]

    static func matches(
        commonName: String?,
        scientificNames: [String?]
    ) -> Bool {
        let normalizedCommonName = normalize(commonName)
        if aliases.contains(normalizedCommonName) { return true }
        return scientificNames.contains {
            aliases.contains(normalize($0))
        }
    }

    private static func normalize(_ value: String?) -> String {
        value?
            .split { $0.isWhitespace }
            .joined(separator: " ")
            .lowercased() ?? ""
    }
}

enum SpeciesIdentificationResolutionPolicy {
    private static let unresolvedNames: Set<String> = [
        "taxonomy unavailable",
        "unknown",
        "unknown subject",
        "unidentified wildlife",
        "no wildlife detected",
        "inanimate object",
        "not applicable",
        "n/a"
    ]

    static func isResolved(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return !normalized.isEmpty && !unresolvedNames.contains(normalized)
    }
}

extension SpeciesData {
    var canUndoIncorrectIdentification: Bool {
        aiReview.state == .aiRejected && !aiReview.needsAttention
            && (aiReview.pending == nil || aiReview.pending?.action == .reject)
    }

    var canMarkIdentificationIncorrect: Bool {
        isBiological && !isHumanSubject && hasResolvedBiologicalIdentification
            && !aiReview.isUnresolved && aiReview.community == nil
            && (aiReview.pending == nil || aiReview.pending?.action == .undo)
            && !aiReview.needsAttention
            && userIdentificationOverride == nil
    }

    /// Prior UI presentation while rejection support has no user-facing surface.
    /// Never use this copy for persistence, statistics, or identification authority.
    var legacyIdentificationPresentation: SpeciesData {
        var presentation = self
        presentation.aiReview = .init()
        return presentation
    }

    /// True for transient inference failures such as network timeouts and
    /// provider-admission decisions. These values use `isBiological == false`
    /// only to avoid biological result UI; they are not model classifications.
    /// The explicit role keeps presentation semantics independent of display copy.
    var isInferenceErrorPlaceholder: Bool {
        presentationRole == .inferenceError
    }

    var isClassifiedNonBiological: Bool {
        !isBiological && !isInferenceErrorPlaceholder
    }

    /// A separate selected taxon, never a replacement for the original AI answer.
    var verifiedConfirmedSpeciesIdentity: ConfirmedSpeciesReview.Identity? {
        guard !aiReview.isUnresolved, isBiological, primaryIdentification?.value != nil,
              let review = confirmedSpeciesReview,
              review.matchesIntent(override: userIdentificationOverride,
                                   confirmed: userConfirmedIdentification,
                                   state: userIdentificationOverride != nil ? .userOverridden : userConfirmedIdentification ? .aiConfirmed : .unreviewed) else { return nil }
        return review.identity
    }

    /// Broad and unresolved biological observations remain usable without a species association.
    var isShareableBiologicalObservation: Bool {
        guard isBiological, !isHumanSubject else { return false }
        if aiReview.isUnresolved { return true }
        if let primaryIdentification { return primaryIdentification.value != nil }
        return hasResolvedBiologicalIdentification
    }

    /// This is deliberately separate from a usable genus/family label.
    var hasSpeciesLevelIdentification: Bool {
        if let community = aiReview.community { return community.rank == "species" }
        if aiReview.isUnresolved { return false }
        if let primaryIdentification {
            return isBiological && primaryIdentification.value?.resolution == .species && userIdentificationOverride == nil
        }
        return hasResolvedBiologicalIdentification
    }

    /// New explicit classifications are durable even when the model abstains
    /// with zero confidence. Legacy confidence-zero behavior stays unchanged.
    var requiresSavedRecord: Bool {
        primaryIdentification?.value != nil || confidenceScore > 0
    }

    var primaryRankDescription: String? {
        switch primaryIdentification?.value?.resolution {
        case .genus: return "Genus-level identification"
        case .family: return "Family-level identification"
        default: return nil
        }
    }

    var hasResolvedBiologicalIdentification: Bool {
        if aiReview.community != nil { return true }
        if aiReview.isUnresolved { return false }
        guard isBiological else { return false }
        if let primaryIdentification {
            return primaryIdentification.value?.resolution.isNamedBiologicalTaxon == true
        }
        let effectiveScientificName = userIdentificationOverride ?? scientificName
        guard SpeciesIdentificationResolutionPolicy.isResolved(
            effectiveScientificName
        ) else { return false }
        if userIdentificationOverride != nil { return true }
        return SpeciesIdentificationResolutionPolicy.isResolved(commonName)
    }

    var isUnresolvedBiologicalSubject: Bool {
        isBiological && !hasResolvedBiologicalIdentification
    }

    /// UI uses the original confidence while review authority remains separate.
    var presentationConfidenceScore: Double? {
        legacyIdentificationPresentation.hasResolvedBiologicalIdentification ? confidenceScore : nil
    }

    /// Audio-only compatibility records may still contain legacy placeholder
    /// names. Presentation derives safe copy without rewriting durable data.
    func subjectDisplayName(isAudioOnlyObservation: Bool) -> String {
        guard isAudioOnlyObservation else { return commonName }
        if isHumanSubject { return "Human" }
        if legacyIdentificationPresentation.isUnresolvedBiologicalSubject { return "Unidentified Wildlife" }
        if isClassifiedNonBiological { return "No wildlife detected" }
        return commonName
    }

    /// True when either the common or effective scientific identity denotes a
    /// Human. Human results suppress candidates and third-party reference media.
    var isHumanSubject: Bool {
        HumanSubjectIdentityPolicy.matches(
            commonName: commonName,
            scientificNames: [scientificName, userIdentificationOverride]
        )
    }

    var presentationScientificName: String {
        isHumanSubject ? "Homo sapiens" : scientificName
    }

    /// Third-party reference photos are not shown for people, domestic cats, or
    /// domestic dogs. Wild felids and canids retain their reference galleries.
    var shouldSuppressReferenceImages: Bool {
        if !legacyIdentificationPresentation.hasSpeciesLevelIdentification { return true }
        return ReferenceImageVisibilityPolicy.shouldSuppress(
            isHumanSubject: isHumanSubject,
            scientificName: scientificName
        )
    }

    /// Splits comma-separated alternative common names, trims blanks, and
    /// de-duplicates case-insensitively while preserving first-seen order.
    static func sanitizeAlternativeNames(_ names: [String]?) -> [String]? {
        guard let names else { return nil }
        let sanitized = names
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let unique = sanitized.filter { seen.insert($0.lowercased()).inserted }
        return unique.isEmpty ? nil : unique
    }
}
