import CoreLocation
import SwiftData
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let scanId: String
    let presentationGeneration: UInt64
    let confidenceScore: Double?
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?
    var onAskCommunity: (() -> Void)?
    let onRequestDismissalAction: (ConfidenceExplanationDismissalAction) -> Void

    @Environment(EnvironmentContextManager.self) private var environmentContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ConfidenceExplanationViewModel
    @State private var showPaywall = false

    init(
        scanId: String,
        presentationGeneration: UInt64,
        confidenceScore: Double?,
        inferenceTier: String?,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        aiScientificName: String? = nil,
        onAskCommunity: (() -> Void)? = nil,
        onRequestDismissalAction: @escaping (
            ConfidenceExplanationDismissalAction
        ) -> Void,
        dependencies: ConfidenceReviewDependencies = .live
    ) {
        self.scanId = scanId
        self.presentationGeneration = presentationGeneration
        self.confidenceScore = confidenceScore
        self.inferenceTier = inferenceTier
        self.userIdentificationOverride = userIdentificationOverride
        self.userConfirmedIdentification = userConfirmedIdentification
        self.isFlagged = isFlagged
        self.aiScientificName = aiScientificName
        self.onAskCommunity = onAskCommunity
        self.onRequestDismissalAction = onRequestDismissalAction
        self._viewModel = State(
            initialValue: ConfidenceExplanationViewModel(
                dependencies: dependencies
            )
        )
    }

    private var showLocationPrompt: Bool {
        let status = environmentContext.locationAuthorizationStatus
        return status == .notDetermined || status == .restricted || status == .denied
    }

    private var refinementAction: (() -> Void)? {
        guard let snapshot = viewModel.refinementSnapshot else { return nil }

        return {
            guard isSubjectPresentationCurrent,
                  snapshot.scanId.caseInsensitiveCompare(scanId) == .orderedSame else {
                return
            }
            if revenueCatManager.isProActive {
                requestDismissalAction(
                    .refineScan(
                        actionContext,
                        initialDescription: snapshot.initialDescription
                    )
                )
            } else {
                showPaywall = true
            }
        }
    }

    private var headerTitle: String {
        ConfidenceExplanationPresentation.headerTitle(
            confidenceScore: confidenceScore,
            hasUserOverride: userIdentificationOverride != nil,
            isUserConfirmed: userConfirmedIdentification
        )
    }

    private var confirmButtonTitle: String {
        ConfidenceExplanationPresentation.confirmButtonTitle(
            commonName: inferenceEngine.speciesData?.commonName,
            aiScientificName: aiScientificName
        )
    }

    private var storedCandidates: [IdentificationCandidate] {
        inferenceEngine.speciesData?.candidates ?? []
    }

    private var visibleReviewCandidates: [IdentificationCandidate] {
        CandidateReviewVisibilityPolicy.visibleCandidates(for: inferenceEngine.speciesData)
    }

    private var swipeModalCandidates: [IdentificationCandidate] {
        if inferenceEngine.speciesData?.alternativesExhausted == true {
            return storedCandidates
        }
        return visibleReviewCandidates
    }

    private var isSubjectPresentationCurrent: Bool {
        viewModel.candidateReview.isCurrent(subject, in: inferenceEngine)
    }

    private var communityRequestAction: (() -> Void)? {
        guard onAskCommunity != nil else { return nil }
        return {
            requestDismissalAction(.askCommunity(actionContext))
        }
    }

    private var actionContext: ConfidenceExplanationActionContext {
        ConfidenceExplanationActionContext(
            scanId: scanId,
            presentationGeneration: presentationGeneration
        )
    }

    private var subject: IdentificationReviewSubject {
        IdentificationReviewSubject(
            scanId: scanId,
            presentationGeneration: presentationGeneration
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                ConfidenceHeader(title: headerTitle)

                let candidates = visibleReviewCandidates
                let storedCandidateCount = storedCandidates.count
                let isExhausted = inferenceEngine.speciesData?.alternativesExhausted == true

                if isExhausted {
                    AllCandidatesReviewedView(
                        candidatesCount: storedCandidateCount,
                        onReviewAgain: {
                            guard isSubjectPresentationCurrent else { return }
                            viewModel.candidateReview.presentSwipeModal(
                                subject: subject
                            )
                        },
                        onReset: {
                            guard isSubjectPresentationCurrent else { return }
                            viewModel.feedback.lightImpact()
                            Task { @MainActor in
                                await viewModel.candidateReview.resetReview(
                                    subject: subject,
                                    inferenceEngine: inferenceEngine,
                                    modelContext: modelContext
                                )
                            }
                        },
                        feedback: viewModel.feedback
                    )
                    .padding(.horizontal, 16)
                } else if let override = userIdentificationOverride {
                    let displayOverride = ConfidenceExplanationPresentation
                        .overrideDisplayName(
                            overrideScientificName: override,
                            commonName: inferenceEngine.speciesData?.commonName
                        )

                    OverriddenView(
                        overrideName: displayOverride,
                        aiScientificName: aiScientificName ?? "Unknown",
                        onUndo: {
                            guard isSubjectPresentationCurrent else { return }
                            viewModel.feedback.lightImpact()
                            Task { @MainActor in
                                await viewModel.candidateReview.resetReview(
                                    subject: subject,
                                    inferenceEngine: inferenceEngine,
                                    modelContext: modelContext
                                )
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if userConfirmedIdentification {
                    ConfirmedView(
                        onReset: {
                            guard isSubjectPresentationCurrent else { return }
                            viewModel.feedback.lightImpact()
                            Task { @MainActor in
                                await viewModel.candidateReview.resetReview(
                                    subject: subject,
                                    inferenceEngine: inferenceEngine,
                                    modelContext: modelContext
                                )
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if !candidates.isEmpty {

                    CandidatesCard(
                        candidates: candidates,
                        aiScientificName: aiScientificName ?? "Unknown subject",
                        inferenceTier: inferenceTier,
                        confirmButtonTitle: confirmButtonTitle,
                        onAskCommunity: communityRequestAction,
                        onMatchConfirmed: nil,
                        onRefineScan: refinementAction,
                        showDismissButton: false,
                        dependencies: viewModel.candidateDependencies
                    )
                    .padding(.horizontal, 16)
                }

                let onReanalyze = refinementAction
                let onAskCommunity = communityRequestAction
                if onReanalyze != nil || onAskCommunity != nil {
                    ConfidenceSheetActionButtons(
                        isReanalyzeLocked: !revenueCatManager.canStartProScan,
                        onReanalyze: onReanalyze,
                        onAskCommunity: onAskCommunity,
                        feedback: viewModel.feedback
                    )
                    .padding(.horizontal, 16)
                }

                if !userConfirmedIdentification && userIdentificationOverride == nil {
                    ConfidenceSpectrum(inferenceTier: inferenceTier)
                }

                if !revenueCatManager.isProActive {
                    PlanCard(
                        showPaywall: $showPaywall,
                        complimentaryDetailContext: .results
                    )
                        .padding(.horizontal, 16)
                }

                ProTips(
                    showLocationPrompt: showLocationPrompt,
                    isProActive: revenueCatManager.isProActive,
                    onOpenSettings: viewModel.openSettings
                )
            }
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .sheet(
            isPresented: swipeModalPresentedBinding,
            onDismiss: resumePendingSwipeDismissalRequest
        ) {
            CandidateSwipeModal(
                isPresented: swipeModalPresentedBinding,
                scanId: scanId,
                presentationGeneration: presentationGeneration,
                candidates: swipeModalCandidates,
                confirmButtonTitle: confirmButtonTitle,
                allowsAskCommunity: communityRequestAction != nil,
                allowsRefinement: refinementAction != nil,
                onRequestDismissalAction: { request in
                    viewModel.candidateReview.stageDismissalRequest(request)
                },
                dependencies: viewModel.candidateDependencies
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onChange(of: inferenceEngine.scanPresentationGeneration) {
            guard !isSubjectPresentationCurrent else { return }
            showPaywall = false
            viewModel.invalidate()
        }
        .task(id: presentationGeneration) {
            guard isSubjectPresentationCurrent else {
                viewModel.invalidate()
                return
            }
            await viewModel.loadRefinementSnapshot(
                subject: subject,
                modelContainer: modelContext.container
            )
            if !isSubjectPresentationCurrent {
                viewModel.invalidate()
            }
        }
    }

    private func requestDismissalAction(
        _ action: ConfidenceExplanationDismissalAction
    ) {
        guard action.context == actionContext, isSubjectPresentationCurrent else {
            return
        }
        onRequestDismissalAction(action)
        dismiss()
    }

    private func resumePendingSwipeDismissalRequest() {
        guard let request = viewModel.candidateReview
            .takePendingDismissalRequest(matching: subject),
            isSubjectPresentationCurrent else { return }

        switch request.action {
        case .applyOverride(let scientificName):
            Task { @MainActor in
                await viewModel.candidateReview.applyOverride(
                    scientificName: scientificName,
                    subject: subject,
                    inferenceEngine: inferenceEngine,
                    modelContext: modelContext
                )
            }
        case .confirmOriginal:
            Task { @MainActor in
                _ = await viewModel.candidateReview.confirmOriginal(
                    subject: subject,
                    inferenceEngine: inferenceEngine,
                    modelContext: modelContext
                )
            }
        case .askCommunity:
            communityRequestAction?()
        case .refineScan:
            refinementAction?()
        }
    }

    private var swipeModalPresentedBinding: Binding<Bool> {
        let expectedSubject = viewModel.candidateReview.swipeModalSubject
        return Binding(
            get: {
                guard viewModel.candidateReview.isSwipeModalPresented,
                      let expectedSubject,
                      expectedSubject.matches(
                          viewModel.candidateReview.swipeModalSubject
                      ) else { return false }
                return viewModel.candidateReview.isCurrent(
                    expectedSubject,
                    in: inferenceEngine
                )
            },
            set: { isPresented in
                guard !isPresented, let expectedSubject else { return }
                viewModel.candidateReview.dismissSwipeModal(
                    ownedBy: expectedSubject
                )
            }
        )
    }
}
