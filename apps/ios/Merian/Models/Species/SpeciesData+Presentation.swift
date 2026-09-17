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

    var hasResolvedBiologicalIdentification: Bool {
        guard isBiological else { return false }
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

    /// Species-match confidence is meaningful only when a taxon was resolved.
    /// Confirmed and override state are presented separately.
    var presentationConfidenceScore: Double? {
        hasResolvedBiologicalIdentification ? confidenceScore : nil
    }

    /// Audio-only compatibility records may still contain legacy placeholder
    /// names. Presentation derives safe copy without rewriting durable data.
    func subjectDisplayName(isAudioOnlyObservation: Bool) -> String {
        guard isAudioOnlyObservation else { return commonName }
        if isHumanSubject { return "Human" }
        if isUnresolvedBiologicalSubject { return "Unidentified Wildlife" }
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
        if !hasResolvedBiologicalIdentification { return true }
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
