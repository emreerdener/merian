import Foundation

struct ConfidenceExplanationActionContext: Sendable, Equatable {
    let scanId: String
    let presentationGeneration: UInt64

    var subject: IdentificationReviewSubject {
        IdentificationReviewSubject(
            scanId: scanId,
            presentationGeneration: presentationGeneration
        )
    }
}

enum ConfidenceExplanationDismissalAction: Sendable, Equatable {
    case askCommunity(ConfidenceExplanationActionContext)
    case refineScan(
        ConfidenceExplanationActionContext,
        initialDescription: String?
    )

    var context: ConfidenceExplanationActionContext {
        switch self {
        case .askCommunity(let context), .refineScan(let context, _):
            context
        }
    }
}

struct ConfidenceBadgePresentation: Equatable {
    enum Style: Equatable {
        case analyzing
        case confirmed
        case strong
        case possible
        case weak
        case unknown
    }

    let label: String
    let icon: String
    let style: Style
    let isVisible: Bool

    var isAnalyzing: Bool {
        style == .analyzing
    }

    static func resolve(
        confidenceScore: Double?,
        inferenceTier: String?,
        hasUserOverride: Bool,
        isUserConfirmed: Bool,
        analyzingPhrase: String?
    ) -> Self {
        if let analyzingPhrase {
            let label = analyzingPhrase.hasSuffix("...")
                ? analyzingPhrase
                : analyzingPhrase + "..."
            return Self(
                label: label,
                icon: "sparkle",
                style: .analyzing,
                isVisible: true
            )
        }
        if hasUserOverride || isUserConfirmed {
            return Self(
                label: "Confirmed",
                icon: "checkmark.circle.fill",
                style: .confirmed,
                isVisible: true
            )
        }
        guard let confidenceScore else {
            return Self(
                label: "Unknown",
                icon: "questionmark",
                style: .unknown,
                isVisible: false
            )
        }

        let bands = MerianConfig.confidenceBands(
            forInferenceTier: inferenceTier
        )
        switch confidenceScore {
        case bands.strong...:
            return Self(
                label: "Strong match",
                icon: "sparkles",
                style: .strong,
                isVisible: confidenceScore > 0
            )
        case bands.possible..<bands.strong:
            return Self(
                label: "Possible match",
                icon: "sparkles",
                style: .possible,
                isVisible: confidenceScore > 0
            )
        default:
            return Self(
                label: "Weak match",
                icon: "sparkles",
                style: .weak,
                isVisible: confidenceScore > 0
            )
        }
    }
}

enum ConfidenceExplanationPresentation {
    static func headerTitle(
        confidenceScore: Double?,
        hasUserOverride: Bool,
        isUserConfirmed: Bool
    ) -> String {
        if hasUserOverride || isUserConfirmed {
            return "Confirmed"
        }
        guard let confidenceScore else { return "Analysis" }
        return "\(Int(round(confidenceScore * 100)))% confident"
    }

    static func confirmButtonTitle(
        commonName: String?,
        aiScientificName: String?
    ) -> String {
        let commonName = commonName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !commonName.isEmpty && commonName.lowercased() != "unknown subject" {
            return "Confirm \(commonName.capitalized)"
        }

        let scientificName = aiScientificName ?? "Unknown"
        let trimmedScientificName = scientificName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmedScientificName.isEmpty &&
            trimmedScientificName.lowercased() != "unknown subject" {
            return "Confirm \(scientificName)"
        }
        return "Confirm initial match"
    }

    static func overrideDisplayName(
        overrideScientificName: String,
        commonName: String?
    ) -> String {
        let commonName = commonName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !commonName.isEmpty,
              commonName.lowercased() != "unknown subject" else {
            return overrideScientificName
        }
        return "\(commonName.capitalized) (\(overrideScientificName))"
    }
}
