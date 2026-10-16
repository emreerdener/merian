import SwiftData
import SwiftUI

extension InsightSheetView {
    var selectedReviewKey: SelectedAnalysisReviewHost.Key? {
        viewModel.toolbarRecordSnapshot?.selectedReviewBaseline.map {
            .init(baseline: $0, generation: viewModel.scanBoundActionGeneration, container: ObjectIdentifier(modelContext.container))
        }
    }

    func permitsLegacyReview(_ scanID: String?) -> Bool {
        guard let scanID else { return false }
        return ObservationHistoryEnrollmentService.permitsLegacyMutation(scanID: scanID, container: modelContext.container)
    }

    func bindSelectedReview() {
        closeSelectedNameConfirmation()
        closeSelectedCandidateReview()
        guard let key = selectedReviewKey, !permitsLegacyReview(key.baseline.observationID.uuidString),
              let access = dependencies.selectedReviewAccess else { selectedReviewHost.close(); return }
        let vm = viewModel
        selectedReviewHost.bind(key, access: access, container: modelContext.container, isCurrent: { [weak vm] in
            guard let vm else { return false }
            return vm.isPresentingLocalRecord(scanId: key.baseline.observationID.uuidString, generation: key.generation)
                && vm.toolbarRecordSnapshot?.selectedReviewBaseline == key.baseline
        })
    }

    func refreshSelectedReview() {
        selectedReviewHost.refresh { key in
            viewModel.refreshAcknowledgedHistory(scanId: key.baseline.observationID.uuidString, generation: key.generation,
                container: modelContext.container, inferenceEngine: inferenceEngine)
        }
        if let message = selectedReviewHost.message { viewModel.state.toastMessage = .information(message) }
    }

    var selectedReviewConfirmationTitle: String {
        guard !permitsLegacyReview(viewModel.presentedLocalRecordScanId),
              let ticket = selectedReviewHost.model?.ticket else { return "Confirm species" }
        if !ticket.canConfirmPrimary, ticket.canConfirmName { return "Confirm species name" }
        guard let name = ticket.primaryScientificName else { return "Confirm species" }
        return "Confirm \(name)"
    }
    func namedReviewAction(scanID: String, generation: UInt64) -> (() -> Void)? {
        guard selectedReviewHost.model?.canSubmit == true,
              selectedReviewHost.model?.ticket.canConfirmName == true, let token = selectedReviewHost.token else { return nil }
        let engineGeneration = inferenceEngine.scanPresentationGeneration
        return {
            guard selectedNameConfirmation == nil, activeShellPresentation == nil,
                  pendingShellPresentation == nil, dismissedShellPresentation == nil else { return }
            let current = {
                viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation)
                    && inferenceEngine.scanPresentationGeneration == engineGeneration
                    && inferenceEngine.speciesData?.scanId?.caseInsensitiveCompare(scanID) == .orderedSame
                    && !permitsLegacyReview(scanID)
            }
            guard let form = selectedReviewHost.prepareNameConfirmation(token: token, isCurrent: current) else { return }
            selectedNameConfirmation = form
            guard requestShellPresentation(.reviewName(formID: form.id, scanId: scanID, generation: generation)) else {
                form.close(); selectedNameConfirmation = nil; return
            }
        }
    }

    func closeSelectedNameConfirmation() {
        selectedNameConfirmation?.close(); selectedNameConfirmation = nil
        cancelOrDismissShellPresentation { if case .reviewName = $0 { true } else { false } }
    }
}

extension InsightSheetView {
    func candidateReviewAction(scanID: String, generation: UInt64) -> (() -> Void)? {
        candidateReviewPreparation(scanID: scanID, generation: generation).map { prepare in
            { prepare()?.resume() }
        }
    }
    func candidateReviewPreparation(scanID: String, generation: UInt64) -> CandidateReviewPreparation? {
        guard selectedReviewHost.model?.canSubmit == true,
              selectedReviewHost.model?.ticket.candidateChoices.isEmpty == false,
              let token = selectedReviewHost.token else { return nil }
        let engineGeneration = inferenceEngine.scanPresentationGeneration
        return {
            guard selectedCandidateReview == nil, activeShellPresentation == nil,
                  pendingShellPresentation == nil, dismissedShellPresentation == nil else { return nil }
            let current = {
                viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation)
                    && inferenceEngine.scanPresentationGeneration == engineGeneration
                    && inferenceEngine.speciesData?.scanId?.caseInsensitiveCompare(scanID) == .orderedSame
                    && !permitsLegacyReview(scanID)
            }
            guard let model = selectedReviewHost.prepareCandidateConfirmation(token: token, isCurrent: current) else { return nil }
            selectedCandidateReview = model
            return CandidateReviewTicket(present: {
                guard selectedCandidateReview === model, model.isScopeCurrent, current(),
                      activeShellPresentation == nil, pendingShellPresentation == nil, dismissedShellPresentation == nil else { return false }
                return requestShellPresentation(.reviewCandidates(formID: model.id, scanId: scanID, generation: generation))
            }, discard: {
                model.close()
                if selectedCandidateReview === model { selectedCandidateReview = nil }
            })
        }
    }
    func closeSelectedCandidateReview() {
        selectedCandidateReview?.close(); selectedCandidateReview = nil
        cancelOrDismissShellPresentation { if case .reviewCandidates = $0 { true } else { false } }
    }
}
