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
              let name = selectedReviewHost.model?.ticket.primaryScientificName else { return "Confirm species" }
        return "Confirm \(name)"
    }
}
