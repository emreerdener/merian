import SwiftUI

// MARK: - Candidates Card

/// Surfaces the AI's alternative identification candidates and collects a one-time
/// user review (Was the AI correct? / Not sure → opens swipe modal).
struct CandidatesCard: View {
    let candidates: [IdentificationCandidate]
    /// The AI's original scientific name — shown in the "overridden" state as "AI suggested X".
    let aiScientificName: String
    let inferenceTier: String?
    /// Called when the user taps "No, incorrect" and there are no candidates to choose from.
    /// The caller should route to the flag/report flow.
    var onFlagIssue: (() -> Void)?
    var onMatchConfirmed: (() -> Void)?
    var showDismissButton: Bool = true

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @State private var isSwipeModalPresented = false
    @State private var dismissedScanId: String?

    private var displayCommonName: String {
        let name = inferenceEngine.speciesData?.commonName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? aiScientificName : name.capitalized
    }

    private var confirmButtonTitle: String {
        let cName = inferenceEngine.speciesData?.commonName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isCommonNameValid = !cName.isEmpty && cName.lowercased() != "unknown subject"
        let isScientificNameValid = !aiScientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && aiScientificName.lowercased() != "unknown subject"
        
        if isCommonNameValid {
            return "Confirm \(cName.capitalized)"
        } else if isScientificNameValid {
            return "Confirm \(aiScientificName)"
        } else {
            return "Confirm initial match"
        }
    }

    private var isWeakMatch: Bool {
        let score = inferenceEngine.speciesData?.confidenceScore ?? 0.0
        let bands = MerianConfig.confidenceBands(forInferenceTier: inferenceTier)
        return score < bands.possible
    }

    var body: some View {
        Group {
            if let scanId = inferenceEngine.speciesData?.scanId, dismissedScanId == scanId {
                EmptyView()
            } else if candidates.isEmpty {
                if isWeakMatch {
                    CandidateVerificationView(
                        confirmButtonTitle: confirmButtonTitle,
                        onConfirm: {
                            HapticManager.shared.triggerSuccessPulse()
                            onMatchConfirmed?()
                            Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                        },
                        onFlagIssue: onFlagIssue,
                        onDismiss: { dismissedScanId = inferenceEngine.speciesData?.scanId },
                        showDismissButton: showDismissButton
                    )
                } else {
                    EmptyView()
                }
            } else {
                CandidateAlternativesView(
                    candidates: candidates,
                    confirmButtonTitle: confirmButtonTitle,
                    isWeakMatch: isWeakMatch,
                    onReviewAlternatives: { isSwipeModalPresented = true },
                    onConfirm: {
                        HapticManager.shared.triggerSuccessPulse()
                        onMatchConfirmed?()
                        Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                    },
                    onDismiss: { dismissedScanId = inferenceEngine.speciesData?.scanId },
                    showDismissButton: showDismissButton
                )
            }
        }
        .sheet(isPresented: $isSwipeModalPresented) {
            CandidateSwipeModal(
                candidates: candidates,
                aiScientificName: aiScientificName,
                confirmButtonTitle: confirmButtonTitle,
                onConfirmOriginal: {
                    onMatchConfirmed?()
                    Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                },
                onFlagIssue: onFlagIssue
            )
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Pending State - Single") {
    CandidatesCard(
        candidates: [
            IdentificationCandidate(scientificName: "Limenitis archippus", commonName: "Viceroy", confidenceScore: 0.71)
        ],
        aiScientificName: "Danaus plexippus",
        inferenceTier: "flash"
    )
    .environment(InferenceEngine())
    .padding()
}

#Preview("Pending State - Pair") {
    CandidatesCard(
        candidates: [
            IdentificationCandidate(scientificName: "Limenitis archippus", commonName: "Viceroy", confidenceScore: 0.71),
            IdentificationCandidate(scientificName: "Danaus gilippus", commonName: "Queen", confidenceScore: 0.58)
        ],
        aiScientificName: "Danaus plexippus",
        inferenceTier: "flash"
    )
    .environment(InferenceEngine())
    .padding()
}
#endif
