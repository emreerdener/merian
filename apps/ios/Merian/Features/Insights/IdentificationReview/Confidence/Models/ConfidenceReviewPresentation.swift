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
        case incorrect
        case awaitingReview
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
        provenance: IdentificationResultProvenance? = nil,
        hasUserOverride: Bool,
        isUserConfirmed: Bool,
        analyzingPhrase: String?,
        review: LocalAIIdentificationReview = .init()
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
        if review.needsAttention {
            return Self(label: "Review needs attention", icon: "exclamationmark.circle", style: .awaitingReview, isVisible: true)
        }
        if review.state == .awaitingAcceptance {
            return Self(label: "Review new result", icon: "questionmark.circle", style: .awaitingReview, isVisible: true)
        }
        if review.state == .aiRejected {
            return Self(label: "Incorrect", icon: "xmark.circle.fill", style: .incorrect, isVisible: true)
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

        guard let bands = InferenceConfidencePolicy.displayBands(
            forInferenceTier: inferenceTier, provenance: provenance
        ) else {
            return Self(label: "Needs review", icon: "questionmark.circle", style: .unknown, isVisible: true)
        }
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
    static func modelDescription(
        inferenceTier: String?,
        provenance: IdentificationResultProvenance? = nil
    ) -> String {
        if provenance?.supportsOpenAIPhotoDisplayBands == true {
            return "This score is the AI’s estimate of the visible identifying features, not a measured probability of a correct identification."
        }
        return inferenceTier == "pro"
            ? "This scan used an enhanced reasoning model for deeper accuracy."
            : "This scan used the standard model optimized for speed. Upgrade to Pro for advanced analysis."
    }

    static func headerTitle(
        confidenceScore: Double?,
        inferenceTier: String? = nil,
        provenance: IdentificationResultProvenance? = nil,
        hasUserOverride: Bool,
        isUserConfirmed: Bool
    ) -> String {
        if hasUserOverride || isUserConfirmed {
            return "Confirmed"
        }
        guard InferenceConfidencePolicy.displayBands(
            forInferenceTier: inferenceTier, provenance: provenance
        ) != nil else { return "Review identification" }
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

/// Actions retain the Shell's exact displayed subject and review receipt.
struct ConfidenceReviewControls {
    enum ConfirmationState: Equatable {
        case primary, named(String)
        static func resolve(_ ticket: ObservationAnalysisReviewTicket) -> Self? {
            if ticket.confirmationAction == .primary, ticket.reviewState == .aiConfirmed { return .primary }
            if ticket.confirmationAction == .name, ticket.reviewState == .userOverridden, let name = ticket.correctionName { return .named(name) }
            return nil
        }
    }
    var confirmationState: ConfirmationState?
    var undo: (() -> Void)?
    var undoConfirmation: (() -> Void)?
    var undoConfirmationRequiresPrompt = false
    var confirmationUndoReason: String?
    var confirmProposal: (() -> Void)?
    var unavailableReason: String?

    func checking(_ isCurrent: @escaping () -> Bool) -> Self {
        Self(confirmationState: confirmationState, undo: undo.map { action in { if isCurrent() { action() } } },
             undoConfirmation: undoConfirmation.map { action in { if isCurrent() { action() } } },
             undoConfirmationRequiresPrompt: undoConfirmationRequiresPrompt, confirmationUndoReason: confirmationUndoReason,
             confirmProposal: confirmProposal.map { action in { if isCurrent() { action() } } },
             unavailableReason: unavailableReason)
    }
}

enum IdentificationReviewNotice {
    static func title(_ review: LocalAIIdentificationReview) -> String {
        if review.needsAttention { return "Review needs attention" }
        return review.state == .aiRejected ? "Marked as incorrect" : "Review new result"
    }

    static func explanation(_ review: LocalAIIdentificationReview) -> String {
        if review.needsAttention {
            return "This review could not be reconciled. Refresh the identification before making another choice."
        }
        if review.state == .aiRejected {
            return "You marked this AI identification as incorrect. Your scan and its original details are preserved."
        }
        return "Reanalysis produced a new proposal. Review it before accepting it; it has not been marked incorrect."
    }

    static func unavailableReason(_ review: LocalAIIdentificationReview) -> String? {
        if review.needsAttention { return "Undo unavailable: this review needs attention." }
        if review.pending != nil { return "Review waiting to sync. Further changes are unavailable until it finishes." }
        if review.state == .aiRejected { return "Undo unavailable: no reversible rejection is available for this identification." }
        return nil
    }
}
