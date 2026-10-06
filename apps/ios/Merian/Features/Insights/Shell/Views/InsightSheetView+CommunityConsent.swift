import SwiftData
import SwiftUI

extension InsightSheetView {
    /// Both engine and shell generations are captured; neither can substitute
    /// the other when an action crosses a child sheet's dismissal.
    var communityConsentPreparation: CommunityConsentPreparation? {
        guard let scanID = viewModel.presentedLocalRecordScanId else { return nil }
        let generation = viewModel.scanBoundActionGeneration
        let legacy = permitsLegacyReview(scanID)
        let token = selectedReviewHost.token
        guard legacy ? viewModel.canRequestCommunityIdentification : selectedReviewHost.hasPublicationAccess else { return nil }
        return { requestedID, engineGeneration in
            guard scanID.caseInsensitiveCompare(requestedID) == .orderedSame,
                  viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation),
                  inferenceEngine.scanPresentationGeneration == engineGeneration,
                  inferenceEngine.speciesData?.scanId?.caseInsensitiveCompare(scanID) == .orderedSame,
                  permitsLegacyReview(scanID) == legacy else { return nil }
            let current = {
                viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation)
                    && inferenceEngine.scanPresentationGeneration == engineGeneration
                    && inferenceEngine.speciesData?.scanId?.caseInsensitiveCompare(scanID) == .orderedSame
                    && permitsLegacyReview(scanID) == legacy
            }
            if legacy {
                return CommunityConsentTicket {
                    guard current() else { return }
                    viewModel.presentCommunityIdentificationRequest(expectedScanId: scanID, expectedGeneration: generation)
                }
            }
            guard let token else { return nil }
            return selectedReviewHost.preparePublication(token: token, container: modelContext.container,
                continuation: publicationContinuation, isCurrent: current) { model in
                    // A prior sheet's dismissal still owns its payload until
                    // completion; never replace that payload with a new chooser.
                    guard current(), selectedPublicationModel == nil,
                          activeShellPresentation == nil, pendingShellPresentation == nil,
                          dismissedShellPresentation == nil else { model.close(); return }
                    selectedPublicationModel = model
                    guard requestShellPresentation(.publicationConsent(scanId: scanID, generation: generation)) else {
                        model.close(); selectedPublicationModel = nil; return
                    }
                    model.startRecovery()
                }
        }
    }

    func closeSelectedPublication() {
        selectedPublicationModel?.close(); selectedPublicationModel = nil
        cancelOrDismissShellPresentation { if case .publicationConsent = $0 { true } else { false } }
    }

    var communityConsentAction: (() -> Void)? {
        guard let prepare = communityConsentPreparation, let scanID = viewModel.presentedLocalRecordScanId else { return nil }
        let engineGeneration = inferenceEngine.scanPresentationGeneration
        return { prepare(scanID, engineGeneration)?.resume() }
    }
}
