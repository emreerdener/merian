import SwiftData
import SwiftUI

/// Holds only the already-prepared action until the sheet has actually dismissed.
@MainActor
struct IdentificationSheetContinuation {
    let scanID: String
    let generation: UInt64
    let isCurrent: () -> Bool
    let resume: () -> Void
    let cancel: () -> Void

    func consume(scanID: String, generation: UInt64) {
        guard self.scanID == scanID, self.generation == generation, isCurrent() else { cancel(); return }
        // Ownership transfers to the resumed operation. Cancelling afterward
        // would abort the SavedReanalysisHandoff task it just started.
        resume()
    }
}

extension InsightSheetView {
    var identificationAction: (() -> Void)? {
        guard let scanID = viewModel.presentedLocalRecordScanId, !viewModel.isProcessing else { return nil }
        let generation = viewModel.scanBoundActionGeneration
        return {
            guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation) else { return }
            _ = requestShellPresentation(.identification(scanId: scanID, generation: generation))
        }
    }

    @ViewBuilder
    func identificationContent(scanID: String, generation: UInt64) -> some View {
        if let species = inferenceEngine.speciesData,
           species.scanId?.caseInsensitiveCompare(scanID) == .orderedSame {
            let engineGeneration = inferenceEngine.scanPresentationGeneration
            let context = ConfidenceExplanationActionContext(scanId: scanID, presentationGeneration: engineGeneration)
            NavigationStack {
                ConfidenceExplanationSheet(
                    scanId: scanID, presentationGeneration: engineGeneration,
                    confidenceScore: species.presentationConfidenceScore,
                    inferenceTier: species.inferenceTier, provenance: species.identificationProvenance,
                    userIdentificationOverride: species.userIdentificationOverride,
                    userConfirmedIdentification: species.userConfirmedIdentification,
                    isFlagged: species.isFlagged,
                    aiScientificName: species.aiScientificName,
                    onAskCommunity: communityConsentAction,
                    onRequestDismissalAction: { action in
                        guard action.context == context else { return }
                        stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration) {
                            switch action {
                            case .reviewCandidates:
                                alternativesReviewAction(scanID: scanID, generation: generation)?()
                            case .askCommunity:
                                guard permitsLegacyReview(scanID) else { return }
                                communityConsentAction?()
                            case .refineScan(_, let description):
                                guard dependencies.savedReanalysisAccess == nil, permitsLegacyReview(scanID) else { return }
                                dependencies.requestRefinement(scanID, description)
                            }
                        }
                    },
                    prepareCommunityConsent: communityConsentPreparation,
                    prepareSavedReanalysis: savedReanalysisPreparation,
                    confidenceReviewControls: confidenceReviewControls,
                    onPreparedCandidateReview: { supplied, ticket in
                        guard supplied == context else { ticket.cancel(); return }
                        stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration,
                            cancel: ticket.cancel, action: ticket.resume)
                    },
                    onPreparedCommunityConsent: { supplied, ticket in
                        guard supplied == context else { ticket.cancel(); return }
                        stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration,
                            cancel: ticket.cancel, action: ticket.resume)
                    },
                    onPreparedReanalysis: { supplied, ticket in
                        guard supplied == context else { ticket.cancel(); return }
                        stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration,
                            cancel: ticket.cancel, action: ticket.resume)
                    },
                    identification: .init(onHistory: historyAction(scanId: scanID, generation: generation, embedded: true),
                    onViewCommunityRequest: (allowsExplorePresentation ? presentedCommunityRequestId : nil).flatMap { requestID in
                        { stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration) {
                            guard presentedCommunityRequestId == requestID else { return }
                            viewModel.presentExplore(target: .communityRequest, expectedScanId: scanID, expectedGeneration: generation)
                        } }
                    },
                    onReanalysisStatus: reanalysisStatusAction(scanId: scanID, generation: generation).map { action in
                        { stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration, action: action) }
                    },
                    onConfirmIdentification: identificationConfirmationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration),
                    onMarkIdentificationIncorrect: incorrectReviewAction(scanID: scanID, generation: generation),
                    onRetryReview: retryReviewAction(),
                    summaryImagePath: presentedRecordSnapshot?.coverImagePath,
                    summaryDate: viewModel.activeRecordTimestamp)
                )
                .id(engineGeneration)
                .navigationDestination(isPresented: $identificationHistoryVisible) {
                    if let historyModel {
                        IdentificationHistorySheet(model: historyModel, candidateRendering: dependencies.candidateRendering,
                            isEmbedded: true, onClose: dismissActiveShellPresentation,
                            onViewReanalysisProgress: reanalysisStatusAction(scanId: scanID, generation: generation).map { action in
                                { stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: inferenceEngine.scanPresentationGeneration, action: action) }
                            }, onViewCommunityRequest: (allowsExplorePresentation ? presentedCommunityRequestId : nil).map { requestID in
                                { stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: inferenceEngine.scanPresentationGeneration) {
                                    guard presentedCommunityRequestId == requestID else { return }
                                    viewModel.presentExplore(target: .communityRequest, expectedScanId: scanID, expectedGeneration: generation)
                                } }
                            })
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .onChange(of: identificationHistoryVisible) { _, visible in
                if !visible { historyModel?.close(); historyModel = nil }
            }
        }
    }

    private func identificationConfirmationAction(scanID: String, generation: UInt64, engineGeneration: UInt64) -> (() -> Void)? {
        guard let action = confirmReviewAction(scanID: scanID, generation: generation) else { return nil }
        // Primary confirmation updates this sheet in place. A broader taxon
        // needs the existing name form, which owns the next Shell presentation.
        guard !permitsLegacyReview(scanID), selectedReviewHost.model?.ticket.canConfirmPrimary != true else { return action }
        return {
            stageIdentificationAction(scanID: scanID, generation: generation, engineGeneration: engineGeneration, action: action)
        }
    }

    func stageIdentificationAction(scanID: String, generation: UInt64, engineGeneration: UInt64,
                                   cancel: @escaping () -> Void = {}, action: @escaping () -> Void) {
        let container = ObjectIdentifier(modelContext.container)
        let authentication = dependencies.authenticationSnapshot()
        let isCurrent = {
            viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation)
                && inferenceEngine.scanPresentationGeneration == engineGeneration
                && inferenceEngine.speciesData?.scanId?.caseInsensitiveCompare(scanID) == .orderedSame
                && ObjectIdentifier(modelContext.container) == container
                && dependencies.authenticationSnapshot() == authentication
        }
        guard isCurrent(), activeShellPresentation == .identification(scanId: scanID, generation: generation) else { cancel(); return }
        cancelIdentificationContinuation()
        identificationContinuation = .init(scanID: scanID, generation: generation, isCurrent: isCurrent, resume: action, cancel: cancel)
        dismissActiveShellPresentation()
    }

    func resumeIdentificationContinuation(scanID: String, generation: UInt64) {
        let continuation = identificationContinuation
        identificationContinuation = nil
        guard let continuation else { return }
        continuation.consume(scanID: scanID, generation: generation)
    }

    func cancelIdentificationContinuation() {
        identificationContinuation?.cancel()
        identificationContinuation = nil
    }

    func closeIdentification() {
        cancelIdentificationContinuation()
        cancelOrDismissShellPresentation { if case .identification = $0 { true } else { false } }
    }
}
