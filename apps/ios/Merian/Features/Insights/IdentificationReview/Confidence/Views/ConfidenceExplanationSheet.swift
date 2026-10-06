import CoreLocation
import SwiftData
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let scanId: String
    let presentationGeneration: UInt64
    let confidenceScore: Double?
    let inferenceTier: String?
    let provenance: IdentificationResultProvenance?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var isFlagged: Bool = false
    var aiScientificName: String?
    var onAskCommunity: (() -> Void)?
    let onRequestDismissalAction: (ConfidenceExplanationDismissalAction) -> Void
    var prepareCommunityConsent: CommunityConsentPreparation?
    @State private var pendingCommunityConsent: CommunityConsentTicket?
    var prepareSavedReanalysis: SavedReanalysisPreparation?
    var onPreparedCommunityConsent: ((ConfidenceExplanationActionContext, CommunityConsentTicket) -> Void)?
    var onPreparedReanalysis: ((ConfidenceExplanationActionContext, SavedReanalysisTicket) -> Void)?
    @State private var pendingReanalysis: SavedReanalysisTicket?

    @Environment(EnvironmentContextManager.self) private var environmentContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ConfidenceExplanationViewModel
    @State private var showPaywall = false
    @State private var showsIncorrectConfirmation = false
    @State private var reviewToast: ToastPayload?
    @State private var reviewToastAction: (() -> Void)?
    @State private var pendingIncorrectSubject: IdentificationReviewSubject?

    init(
        scanId: String,
        presentationGeneration: UInt64,
        confidenceScore: Double?,
        inferenceTier: String?,
        provenance: IdentificationResultProvenance? = nil,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        aiScientificName: String? = nil,
        onAskCommunity: (() -> Void)? = nil,
        onRequestDismissalAction: @escaping (
            ConfidenceExplanationDismissalAction
        ) -> Void,
        prepareCommunityConsent: CommunityConsentPreparation? = nil,
        prepareSavedReanalysis: SavedReanalysisPreparation? = nil,
        onPreparedCommunityConsent: ((ConfidenceExplanationActionContext, CommunityConsentTicket) -> Void)? = nil,
        onPreparedReanalysis: ((ConfidenceExplanationActionContext, SavedReanalysisTicket) -> Void)? = nil,
        dependencies: ConfidenceReviewDependencies = .live
    ) {
        self.scanId = scanId
        self.presentationGeneration = presentationGeneration
        self.confidenceScore = confidenceScore
        self.inferenceTier = inferenceTier
        self.provenance = provenance
        self.userIdentificationOverride = userIdentificationOverride
        self.userConfirmedIdentification = userConfirmedIdentification
        self.isFlagged = isFlagged
        self.aiScientificName = aiScientificName
        self.onAskCommunity = onAskCommunity
        self.onRequestDismissalAction = onRequestDismissalAction
        self.prepareCommunityConsent = prepareCommunityConsent
        self.prepareSavedReanalysis = prepareSavedReanalysis
        self.onPreparedCommunityConsent = onPreparedCommunityConsent
        self.onPreparedReanalysis = onPreparedReanalysis
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
        if let prepareSavedReanalysis {
            return {
                guard isSubjectPresentationCurrent else { return }
                dismissWithPreparedReanalysis(prepareSavedReanalysis(scanId, presentationGeneration))
            }
        }
        guard permitsLegacyReview, let snapshot = viewModel.refinementSnapshot else { return nil }

        return {
            guard permitsLegacyReview, isSubjectPresentationCurrent,
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
        if inferenceEngine.speciesData?.aiReview.isUnresolved == true { return "Incorrect" }
        return ConfidenceExplanationPresentation.headerTitle(
            confidenceScore: confidenceScore,
            inferenceTier: inferenceTier,
            provenance: provenance,
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
        guard onAskCommunity != nil || prepareCommunityConsent != nil else { return nil }
        return {
            if let prepareCommunityConsent {
                guard let ticket = prepareCommunityConsent(scanId, presentationGeneration) else { return }
                dismissWithPreparedCommunityConsent(ticket)
                return
            }
            guard permitsLegacyReview else { return }
            requestDismissalAction(.askCommunity(actionContext))
        }
    }

    private var permitsLegacyReview: Bool {
        ObservationHistoryEnrollmentService.permitsLegacyMutation(scanID: scanId, container: modelContext.container)
    }

    private var undoIncorrectAction: (() -> Void)? {
        guard permitsLegacyReview, isSubjectPresentationCurrent,
              inferenceEngine.speciesData?.canUndoIncorrectIdentification == true else { return nil }
        let expectedSubject = subject
        return { undoIncorrect(expectedSubject: expectedSubject) }
    }

    private func undoIncorrect(expectedSubject: IdentificationReviewSubject) {
        Task { @MainActor in
            guard permitsLegacyReview, expectedSubject.matches(subject), isSubjectPresentationCurrent,
                  inferenceEngine.speciesData?.canUndoIncorrectIdentification == true else { return }
            reviewToast = nil
            reviewToastAction = nil
            await inferenceEngine.undoIncorrectIdentification(expectedScanId: expectedSubject.scanId, modelContext: modelContext)
        }
    }

    private var incorrectAction: (() -> Void)? {
        guard permitsLegacyReview, isSubjectPresentationCurrent,
              viewModel.refinementSnapshot != nil,
              inferenceEngine.speciesData?.canMarkIdentificationIncorrect == true else { return nil }
        return {
            pendingIncorrectSubject = subject
            showsIncorrectConfirmation = true
        }
    }

    private func confirmIncorrectIdentification() {
        guard let expectedSubject = pendingIncorrectSubject else { return }
        pendingIncorrectSubject = nil
        Task { @MainActor in
            guard permitsLegacyReview, expectedSubject.matches(subject), isSubjectPresentationCurrent,
                  inferenceEngine.speciesData?.canMarkIdentificationIncorrect == true else { return }
            await inferenceEngine.markIdentificationIncorrect(
                expectedScanId: scanId,
                modelContext: modelContext,
                onLocalSave: {
                    guard permitsLegacyReview, expectedSubject.matches(subject), isSubjectPresentationCurrent else { return }
                    reviewToastAction = { undoIncorrect(expectedSubject: expectedSubject) }
                    reviewToast = .information("Marked as incorrect", action: .init(id: .undo, title: "Undo"))
                }
            )
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
                ConfidenceHeader(
                    title: headerTitle,
                    showsExplanation: inferenceEngine.speciesData?.aiReview.isUnresolved != true
                        && !userConfirmedIdentification && userIdentificationOverride == nil
                )

                if inferenceEngine.speciesData?.aiReview.isUnresolved == true {
                    IncorrectIdentificationView(onUndo: undoIncorrectAction)
                        .padding(.horizontal, 16)
                }

                let candidates = visibleReviewCandidates
                let storedCandidateCount = storedCandidates.count
                let isExhausted = inferenceEngine.speciesData?.alternativesExhausted == true

                if !permitsLegacyReview {
                    EmptyView()
                } else if isExhausted {
                    AllCandidatesReviewedView(
                        candidatesCount: storedCandidateCount,
                        onReviewAgain: {
                            guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
                            viewModel.candidateReview.presentSwipeModal(
                                subject: subject
                            )
                        },
                        onReset: {
                            guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
                            viewModel.feedback.lightImpact()
                            Task { @MainActor in
                                guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
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
                            guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
                            viewModel.feedback.lightImpact()
                            Task { @MainActor in
                                guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
                                await viewModel.candidateReview.resetReview(
                                    subject: subject,
                                    inferenceEngine: inferenceEngine,
                                    modelContext: modelContext
                                )
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                } else if userConfirmedIdentification && inferenceEngine.speciesData?.aiReview.isUnresolved != true {
                    ConfirmedView(
                        onReset: {
                            guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
                            viewModel.feedback.lightImpact()
                            Task { @MainActor in
                                guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
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
                        prepareCommunityConsent: prepareCommunityConsent,
                        prepareSavedReanalysis: prepareSavedReanalysis,
                        resumeCommunityConsent: dismissWithPreparedCommunityConsent,
                        resumeSavedReanalysis: dismissWithPreparedReanalysis,
                        showDismissButton: false,
                        dependencies: viewModel.candidateDependencies
                    )
                    .padding(.horizontal, 16)
                }

                let onReanalyze = refinementAction
                let onAskCommunity = communityRequestAction
                if onReanalyze != nil || onAskCommunity != nil || incorrectAction != nil {
                    ConfidenceSheetActionButtons(
                        isReanalyzeLocked: prepareSavedReanalysis == nil && !revenueCatManager.canStartProScan,
                        onReanalyze: onReanalyze,
                        onAskCommunity: onAskCommunity,
                        onMarkIncorrect: incorrectAction,
                        feedback: viewModel.feedback
                    )
                    .padding(.horizontal, 16)
                }

                if !userConfirmedIdentification && userIdentificationOverride == nil {
                    ConfidenceSpectrum(inferenceTier: inferenceTier, provenance: provenance)
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
        .alert("Identification confirmation", isPresented: Binding(
            get: { viewModel.candidateReview.confirmationMessage != nil },
            set: { if !$0 { viewModel.candidateReview.confirmationMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.candidateReview.confirmationMessage = nil }
        } message: {
            Text(viewModel.candidateReview.confirmationMessage ?? "")
        }
        .alert("Mark identification as incorrect?", isPresented: $showsIncorrectConfirmation) {
            Button("Mark as incorrect", role: .destructive, action: confirmIncorrectIdentification)
            Button("Cancel", role: .cancel) { pendingIncorrectSubject = nil }
        } message: {
            Text("Your scan, photos, and notes will be kept.")
        }
        .merianSystemFeedback(toast: $reviewToast, toastAction: $reviewToastAction, showsAchievementToasts: false)
        .transparentTopToolbar()
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
                    pendingCommunityConsent?.cancel(); pendingCommunityConsent = nil
                    if case .askCommunity = request.action, let prepareCommunityConsent {
                        pendingCommunityConsent = prepareCommunityConsent(request.scanId, request.presentationGeneration)
                    }
                    pendingReanalysis?.cancel()
                    pendingReanalysis = nil
                    if case .refineScan = request.action, let prepareSavedReanalysis {
                        pendingReanalysis = prepareSavedReanalysis(request.scanId, request.presentationGeneration)
                    }
                    viewModel.candidateReview.stageDismissalRequest(request)
                },
                dependencies: viewModel.candidateDependencies
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onDisappear {
            pendingCommunityConsent?.cancel(); pendingCommunityConsent = nil
            pendingReanalysis?.cancel()
            pendingReanalysis = nil
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

    private func dismissWithPreparedCommunityConsent(_ ticket: CommunityConsentTicket) {
        guard isSubjectPresentationCurrent, let onPreparedCommunityConsent else { ticket.cancel(); return }
        onPreparedCommunityConsent(actionContext, ticket)
        dismiss()
    }

    private func dismissWithPreparedReanalysis(_ ticket: SavedReanalysisTicket) {
        guard isSubjectPresentationCurrent, let onPreparedReanalysis else { ticket.cancel(); return }
        onPreparedReanalysis(actionContext, ticket)
        dismiss()
    }

    private func resumePendingSwipeDismissalRequest() {
        let community = pendingCommunityConsent
        pendingCommunityConsent = nil
        var communityForwarded = false
        defer { if !communityForwarded { community?.cancel() } }
        let prepared = pendingReanalysis
        pendingReanalysis = nil
        guard let request = viewModel.candidateReview
            .takePendingDismissalRequest(matching: subject),
            isSubjectPresentationCurrent else { prepared?.cancel(); return }
        if case .refineScan = request.action {} else { prepared?.cancel() }

        switch request.action {
        case .applyOverride(let scientificName):
            Task { @MainActor in
                guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
                await viewModel.candidateReview.applyOverride(
                    scientificName: scientificName,
                    subject: subject,
                    inferenceEngine: inferenceEngine,
                    modelContext: modelContext
                )
            }
        case .confirmOriginal:
            Task { @MainActor in
                guard permitsLegacyReview, isSubjectPresentationCurrent else { return }
                _ = await viewModel.candidateReview.confirmOriginal(
                    subject: subject,
                    inferenceEngine: inferenceEngine,
                    modelContext: modelContext
                )
            }
        case .askCommunity:
            if let community { communityForwarded = true; dismissWithPreparedCommunityConsent(community); return }
            guard prepareCommunityConsent == nil, permitsLegacyReview else { return }
            communityRequestAction?()
        case .refineScan:
            if let prepared { dismissWithPreparedReanalysis(prepared); return }
            guard prepareSavedReanalysis == nil else { return }
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
