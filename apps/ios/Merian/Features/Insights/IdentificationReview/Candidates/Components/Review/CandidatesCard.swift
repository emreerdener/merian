import SwiftData
import SwiftUI

// MARK: - Candidates Card

/// Surfaces the AI's alternative identification candidates and collects a one-time
/// user review (Was the AI correct? / Not sure → opens swipe modal).
struct CandidatesCard: View {
    let candidates: [IdentificationCandidate]
    let inferenceTier: String?
    let confirmButtonTitle: String
    /// Called when the user wants human help because the AI/candidates did not resolve the ID.
    var onAskCommunity: (() -> Void)?
    var onMatchConfirmed: (() -> Void)?
    var onRefineScan: (() -> Void)?
    var prepareCommunityConsent: CommunityConsentPreparation?
    @State private var pendingCommunityConsent: CommunityConsentTicket?
    var prepareSavedReanalysis: SavedReanalysisPreparation?
    var resumeCommunityConsent: ((CommunityConsentTicket) -> Void)?
    var resumeSavedReanalysis: ((SavedReanalysisTicket) -> Void)?
    @State private var pendingReanalysis: SavedReanalysisTicket?
    var showDismissButton: Bool = true

    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CandidateReviewViewModel

    init(
        candidates: [IdentificationCandidate],
        aiScientificName: String,
        inferenceTier: String?,
        confirmButtonTitle: String,
        onAskCommunity: (() -> Void)? = nil,
        onMatchConfirmed: (() -> Void)? = nil,
        onRefineScan: (() -> Void)? = nil,
        prepareCommunityConsent: CommunityConsentPreparation? = nil,
        prepareSavedReanalysis: SavedReanalysisPreparation? = nil,
        resumeCommunityConsent: ((CommunityConsentTicket) -> Void)? = nil,
        resumeSavedReanalysis: ((SavedReanalysisTicket) -> Void)? = nil,
        showDismissButton: Bool = true,
        dependencies: CandidateReviewDependencies = .live
    ) {
        self.candidates = candidates
        // Retain the established call-site label while name presentation remains
        // sourced from the current engine result and candidate values.
        _ = aiScientificName
        self.inferenceTier = inferenceTier
        self.confirmButtonTitle = confirmButtonTitle
        self.onAskCommunity = onAskCommunity
        self.onMatchConfirmed = onMatchConfirmed
        self.onRefineScan = onRefineScan
        self.prepareCommunityConsent = prepareCommunityConsent
        self.prepareSavedReanalysis = prepareSavedReanalysis
        self.resumeCommunityConsent = resumeCommunityConsent
        self.resumeSavedReanalysis = resumeSavedReanalysis
        self.showDismissButton = showDismissButton
        self._viewModel = State(
            initialValue: CandidateReviewViewModel(dependencies: dependencies)
        )
    }

    private func permitsLegacyReview(_ scanID: String?) -> Bool {
        guard let scanID else { return false }
        return ObservationHistoryEnrollmentService.permitsLegacyMutation(scanID: scanID, container: modelContext.container)
    }

    private var isWeakMatch: Bool {
        let score = inferenceEngine.speciesData?.confidenceScore ?? 0.0
        guard let bands = inferenceEngine.speciesData?.identificationConfidenceBands else {
            return false
        }
        return score < bands.possible
    }

    private func isSubjectPresentationCurrent(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        viewModel.isCurrent(
            IdentificationReviewSubject(
                scanId: scanId,
                presentationGeneration: generation
            ),
            in: inferenceEngine
        )
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

    private func confirmOriginal(scanId: String, generation: UInt64, expectedReview: LocalAIIdentificationReview?) async {
        guard let expectedReview, permitsLegacyReview(scanId), isSubjectPresentationCurrent(
            scanId: scanId,
            generation: generation
        ) else {
            return
        }
        let subject = IdentificationReviewSubject(
            scanId: scanId,
            presentationGeneration: generation
        )
        guard await viewModel.confirmOriginal(
            subject: subject,
            inferenceEngine: inferenceEngine,
            modelContext: modelContext, expectedReview: expectedReview
        ) else { return }
        viewModel.feedback.successPulse()
        onMatchConfirmed?()
    }

    var body: some View {
        let presentedScanId = inferenceEngine.speciesData?.scanId
        let presentedGeneration = inferenceEngine.scanPresentationGeneration
        let presentedReview = inferenceEngine.speciesData?.aiReview
        let guardedAskCommunity = guardedAction(
            onAskCommunity,
            scanId: presentedScanId,
            generation: presentedGeneration
        )
        Group {
            if !permitsLegacyReview(presentedScanId) {
                if let guardedAskCommunity { Button("Ask the community", action: guardedAskCommunity) }
            } else if viewModel.shouldHideCard(scanId: presentedScanId) {
                EmptyView()
            } else if candidates.isEmpty {
                CandidateVerificationView(
                    isWeakMatch: isWeakMatch,
                    confirmButtonTitle: confirmButtonTitle,
                    onConfirm: {
                        guard let presentedScanId else { return }
                        await confirmOriginal(
                            scanId: presentedScanId,
                            generation: presentedGeneration, expectedReview: presentedReview
                        )
                    },
                    onAskCommunity: guardedAskCommunity,
                    onDismiss: {
                        guard let presentedScanId, permitsLegacyReview(presentedScanId),
                              isSubjectPresentationCurrent(
                                  scanId: presentedScanId,
                                  generation: presentedGeneration
                              ) else {
                            return
                        }
                        viewModel.dismissCard(
                            subject: IdentificationReviewSubject(
                                scanId: presentedScanId,
                                presentationGeneration: presentedGeneration
                            )
                        )
                    },
                    showDismissButton: showDismissButton,
                    showsOriginalConfirmation: inferenceEngine.speciesData?.aiReview.isUnresolved != true,
                    feedback: viewModel.feedback
                )
            } else {
                CandidateAlternativesView(
                    candidates: candidates,
                    confirmButtonTitle: confirmButtonTitle,
                    isWeakMatch: isWeakMatch,
                    onReviewAlternatives: {
                        guard let presentedScanId, permitsLegacyReview(presentedScanId),
                              isSubjectPresentationCurrent(
                                  scanId: presentedScanId,
                                  generation: presentedGeneration
                              ) else {
                            return
                        }
                        viewModel.presentSwipeModal(
                            subject: IdentificationReviewSubject(
                                scanId: presentedScanId,
                                presentationGeneration: presentedGeneration
                            )
                        )
                    },
                    onConfirm: {
                        guard let presentedScanId else { return }
                        await confirmOriginal(
                            scanId: presentedScanId,
                            generation: presentedGeneration, expectedReview: presentedReview
                        )
                    },
                    onDismiss: {
                        guard let presentedScanId, permitsLegacyReview(presentedScanId),
                              isSubjectPresentationCurrent(
                                  scanId: presentedScanId,
                                  generation: presentedGeneration
                              ) else {
                            return
                        }
                        viewModel.dismissCard(
                            subject: IdentificationReviewSubject(
                                scanId: presentedScanId,
                                presentationGeneration: presentedGeneration
                            )
                        )
                    },
                    showDismissButton: showDismissButton,
                    showsOriginalConfirmation: inferenceEngine.speciesData?.aiReview.isUnresolved != true,
                    imageDependencies: viewModel.imageDependencies,
                    feedback: viewModel.feedback
                )
            }
        }
        .id("\(presentedScanId ?? ""):\(presentedGeneration)")
        .alert("Identification confirmation", isPresented: Binding(
            get: { viewModel.confirmationMessage != nil },
            set: { if !$0 { viewModel.confirmationMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.confirmationMessage = nil }
        } message: {
            Text(viewModel.confirmationMessage ?? "")
        }
        .sheet(
            isPresented: swipeModalPresentedBinding,
            onDismiss: resumePendingSwipeDismissalRequest
        ) {
            if let subject = viewModel.swipeModalSubject,
               isSubjectPresentationCurrent(
                   scanId: subject.scanId,
                   generation: subject.presentationGeneration
               ) {
                CandidateSwipeModal(
                    isPresented: swipeModalPresentedBinding,
                    scanId: subject.scanId,
                    presentationGeneration: subject.presentationGeneration,
                    candidates: candidates,
                    confirmButtonTitle: confirmButtonTitle,
                    allowsAskCommunity: onAskCommunity != nil,
                    allowsRefinement: onRefineScan != nil,
                    onRequestDismissalAction: { request in
                        pendingCommunityConsent?.cancel(); pendingCommunityConsent = nil
                        if case .askCommunity = request.action, let prepareCommunityConsent {
                            pendingCommunityConsent = prepareCommunityConsent(request.scanId, request.presentationGeneration)
                        }
                        pendingReanalysis?.cancel()
                        pendingReanalysis = nil
                        if case .refineScan = request.action, let prepareSavedReanalysis {
                            pendingReanalysis = prepareSavedReanalysis(request.scanId, request.presentationGeneration)
                        }
                        viewModel.stageDismissalRequest(request)
                    },
                    dependencies: viewModel.childDependencies
                )
            }
        }
        .onDisappear {
            pendingCommunityConsent?.cancel(); pendingCommunityConsent = nil
            pendingReanalysis?.cancel()
            pendingReanalysis = nil
        }
        .onChange(of: presentedScanId) {
            viewModel.invalidateSwipeModal()
        }
        .onChange(of: inferenceEngine.scanPresentationGeneration) {
            viewModel.invalidateSwipeModal()
        }
    }

    private var swipeModalPresentedBinding: Binding<Bool> {
        let expectedSubject = viewModel.swipeModalSubject
        return Binding(
            get: {
                guard viewModel.isSwipeModalPresented,
                      let expectedSubject,
                      expectedSubject.matches(viewModel.swipeModalSubject) else {
                    return false
                }
                return viewModel.isCurrent(
                    expectedSubject,
                    in: inferenceEngine
                )
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let expectedSubject else { return }
                viewModel.dismissSwipeModal(ownedBy: expectedSubject)
            }
        )
    }

    private func resumePendingSwipeDismissalRequest() {
        let community = pendingCommunityConsent
        pendingCommunityConsent = nil
        var communityForwarded = false
        defer { if !communityForwarded { community?.cancel() } }
        let prepared = pendingReanalysis
        pendingReanalysis = nil
        guard let currentScanId = inferenceEngine.speciesData?.scanId else {
            viewModel.invalidateSwipeModal()
            prepared?.cancel()
            return
        }
        let currentSubject = IdentificationReviewSubject(
            scanId: currentScanId,
            presentationGeneration: inferenceEngine.scanPresentationGeneration
        )
        guard let request = viewModel.takePendingDismissalRequest(
            matching: currentSubject
        ) else { prepared?.cancel(); return }
        if case .refineScan = request.action {} else { prepared?.cancel() }

        switch request.action {
        case .applyOverride(let scientificName):
            Task { @MainActor in
                guard let expectedReview = request.expectedReview, permitsLegacyReview(request.scanId) else { return }
                await viewModel.applyOverride(
                    scientificName: scientificName,
                    subject: request.subject,
                    inferenceEngine: inferenceEngine,
                    modelContext: modelContext, expectedReview: expectedReview
                )
            }
        case .confirmOriginal:
            Task { @MainActor in
                await confirmOriginal(
                    scanId: request.scanId,
                    generation: request.presentationGeneration, expectedReview: request.expectedReview
                )
            }
        case .askCommunity:
            if let community {
                if let resumeCommunityConsent { communityForwarded = true; resumeCommunityConsent(community) } else { community.resume() }
                return
            }
            guard prepareCommunityConsent == nil, permitsLegacyReview(request.scanId) else { return }
            onAskCommunity?()
        case .refineScan:
            if let prepared {
                if let resumeSavedReanalysis { resumeSavedReanalysis(prepared) } else { prepared.resume() }
                return
            }
            guard prepareSavedReanalysis == nil else { return }
            onRefineScan?()
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
        confirmButtonTitle: "Confirm Monarch",
        dependencies: CandidateReviewDependencies()
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
        confirmButtonTitle: "Confirm Monarch",
        dependencies: CandidateReviewDependencies()
    )
    .environment(InferenceEngine())
    .padding()
}
#endif
