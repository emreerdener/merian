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
    @State private var swipeModalScanId: String?
    @State private var swipeModalGeneration: UInt64?
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

    private func isSubjectPresentationCurrent(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        inferenceEngine.scanPresentationGeneration == generation &&
            inferenceEngine.speciesData?.scanId?
                .caseInsensitiveCompare(scanId) == .orderedSame
    }

    private func guardedAction(
        _ action: (() -> Void)?,
        scanId: String?,
        generation: UInt64
    ) -> (() -> Void)? {
        guard let action, let scanId else { return nil }
        return {
            guard isSubjectPresentationCurrent(
                scanId: scanId,
                generation: generation
            ) else {
                return
            }
            action()
        }
    }

    private func confirmOriginal(scanId: String, generation: UInt64) {
        guard isSubjectPresentationCurrent(
            scanId: scanId,
            generation: generation
        ) else {
            return
        }
        HapticManager.shared.triggerSuccessPulse()
        Task { @MainActor in
            guard isSubjectPresentationCurrent(
                scanId: scanId,
                generation: generation
            ) else {
                return
            }
            await inferenceEngine.confirmAIIdentification(
                expectedScanId: scanId,
                modelContext: modelContext
            )
            guard isSubjectPresentationCurrent(
                scanId: scanId,
                generation: generation
            ) else {
                return
            }
            onMatchConfirmed?()
        }
    }

    var body: some View {
        let presentedScanId = inferenceEngine.speciesData?.scanId
        let presentedGeneration = inferenceEngine.scanPresentationGeneration
        let guardedAskCommunity = guardedAction(
            onAskCommunity,
            scanId: presentedScanId,
            generation: presentedGeneration
        )
        let guardedRefineScan = guardedAction(
            onRefineScan,
            scanId: presentedScanId,
            generation: presentedGeneration
        )

        Group {
            if let presentedScanId, dismissedScanId == presentedScanId {
                EmptyView()
            } else if candidates.isEmpty {
                CandidateVerificationView(
                    isWeakMatch: isWeakMatch,
                    confirmButtonTitle: confirmButtonTitle,
                    onConfirm: {
                        guard let presentedScanId else { return }
                        confirmOriginal(
                            scanId: presentedScanId,
                            generation: presentedGeneration
                        )
                    },
                    onAskCommunity: guardedAskCommunity,
                    onRefineScan: guardedRefineScan,
                    onDismiss: {
                        guard let presentedScanId,
                              isSubjectPresentationCurrent(
                                  scanId: presentedScanId,
                                  generation: presentedGeneration
                              ) else {
                            return
                        }
                        dismissedScanId = presentedScanId
                    },
                    showDismissButton: showDismissButton
                )
            } else {
                CandidateAlternativesView(
                    candidates: candidates,
                    confirmButtonTitle: confirmButtonTitle,
                    isWeakMatch: isWeakMatch,
                    onReviewAlternatives: {
                        guard let presentedScanId,
                              isSubjectPresentationCurrent(
                                  scanId: presentedScanId,
                                  generation: presentedGeneration
                              ) else {
                            return
                        }
                        swipeModalScanId = presentedScanId
                        swipeModalGeneration = presentedGeneration
                        isSwipeModalPresented = true
                    },
                    onConfirm: {
                        guard let presentedScanId else { return }
                        confirmOriginal(
                            scanId: presentedScanId,
                            generation: presentedGeneration
                        )
                    },
                    onRefineScan: guardedRefineScan,
                    onDismiss: {
                        guard let presentedScanId,
                              isSubjectPresentationCurrent(
                                  scanId: presentedScanId,
                                  generation: presentedGeneration
                              ) else {
                            return
                        }
                        dismissedScanId = presentedScanId
                    },
                    showDismissButton: showDismissButton
                )
            }
        }
        .sheet(isPresented: swipeModalPresentedBinding) {
            if let swipeModalScanId,
               let swipeModalGeneration,
               isSubjectPresentationCurrent(
                   scanId: swipeModalScanId,
                   generation: swipeModalGeneration
               ) {
                CandidateSwipeModal(
                    isPresented: swipeModalPresentedBinding,
                    scanId: swipeModalScanId,
                    presentationGeneration: swipeModalGeneration,
                    candidates: candidates,
                    aiScientificName: aiScientificName,
                    confirmButtonTitle: confirmButtonTitle,
                    onConfirmOriginal: {
                        confirmOriginal(
                            scanId: swipeModalScanId,
                            generation: swipeModalGeneration
                        )
                    },
                    onAskCommunity: guardedAction(
                        onAskCommunity,
                        scanId: swipeModalScanId,
                        generation: swipeModalGeneration
                    ),
                    onRefineScan: guardedAction(
                        onRefineScan,
                        scanId: swipeModalScanId,
                        generation: swipeModalGeneration
                    )
                )
            }
        }
        .onChange(of: presentedScanId) {
            isSwipeModalPresented = false
            swipeModalScanId = nil
            swipeModalGeneration = nil
        }
        .onChange(of: inferenceEngine.scanPresentationGeneration) {
            isSwipeModalPresented = false
            swipeModalScanId = nil
            swipeModalGeneration = nil
        }
    }

    private var swipeModalPresentedBinding: Binding<Bool> {
        let expectedScanId = swipeModalScanId
        let expectedGeneration = swipeModalGeneration
        return Binding(
            get: {
                guard isSwipeModalPresented,
                      let expectedScanId,
                      let expectedGeneration,
                      swipeModalScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      swipeModalGeneration == expectedGeneration else {
                    return false
                }
                return isSubjectPresentationCurrent(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedScanId,
                      let expectedGeneration,
                      swipeModalScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      swipeModalGeneration == expectedGeneration else {
                    return
                }
                isSwipeModalPresented = false
                swipeModalScanId = nil
                swipeModalGeneration = nil
            }
        )
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
