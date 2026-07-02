import SwiftUI

// MARK: - Candidates Card

/// Surfaces the AI's alternative identification candidates and collects a one-time
/// user review (Was the AI correct? / Not sure → opens swipe modal).
struct CandidatesCard: View {
    let candidates: [IdentificationCandidate]
    /// The AI's original scientific name — shown in the "overridden" state as "AI suggested X".
    let aiScientificName: String
    let inferenceTier: String?
    let confirmButtonTitle: String
    /// Called when the user wants human help because the AI/candidates did not resolve the ID.
    var onAskCommunity: (() -> Void)?
    var onMatchConfirmed: (() -> Void)?
    var onRefineScan: (() -> Void)?
    var showDismissButton: Bool = true

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @State private var isSwipeModalPresented = false
    @State private var dismissedScanId: String?

    private var displayCommonName: String {
        let name = inferenceEngine.speciesData?.commonName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? aiScientificName : name.capitalized
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
                CandidateVerificationView(
                    isWeakMatch: isWeakMatch,
                    confirmButtonTitle: confirmButtonTitle,
                    onConfirm: {
                        HapticManager.shared.triggerSuccessPulse()
                        onMatchConfirmed?()
                        Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                    },
                    onAskCommunity: onAskCommunity,
                    onRefineScan: onRefineScan,
                    onDismiss: { dismissedScanId = inferenceEngine.speciesData?.scanId },
                    showDismissButton: showDismissButton
                )
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
                    onRefineScan: onRefineScan,
                    onDismiss: { dismissedScanId = inferenceEngine.speciesData?.scanId },
                    showDismissButton: showDismissButton
                )
            }
        }
        .sheet(isPresented: $isSwipeModalPresented) {
            CandidateSwipeModal(
                isPresented: $isSwipeModalPresented,
                candidates: candidates,
                aiScientificName: aiScientificName,
                confirmButtonTitle: confirmButtonTitle,
                onConfirmOriginal: {
                    onMatchConfirmed?()
                    Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
                },
                onAskCommunity: onAskCommunity,
                onRefineScan: onRefineScan
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
        inferenceTier: "flash",
        confirmButtonTitle: "Confirm Monarch"
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
        inferenceTier: "flash",
        confirmButtonTitle: "Confirm Monarch"
    )
    .environment(InferenceEngine())
    .padding()
}
#endif
