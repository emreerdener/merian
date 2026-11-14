import SwiftData
import SwiftUI

extension InsightSheetView {
    func historyAction(scanId: String?, generation: UInt64) -> (() -> Void)? {
        _ = historyAvailabilityRevision
        guard let scanId, let access = dependencies.historyAccess,
              access.hasMultiple(scanId, modelContext.container) else { return nil }
        return {
            guard viewModel.isPresentingLocalRecord(scanId: scanId, generation: generation),
                  historyModel == nil,
                  access.hasMultiple(scanId, modelContext.container) else { return }
            do {
                let service = try access.open(scanId, modelContext.container)
                if service.publicationConsent != nil {
                    let context = try service.context()
                    publicationContinuation.bind(owner: context.owner, observation: try ObservationHistoryPage.uuid(scanId),
                        container: modelContext.container)
                }
                historyModel?.close()
                historyModel = IdentificationHistoryViewModel(dependencies: service, isPresented: {
                    viewModel.isPresentingLocalRecord(scanId: scanId, generation: generation)
                }, didAdmit: {
                    viewModel.refreshAcknowledgedHistory(scanId: scanId, generation: generation,
                        container: modelContext.container, inferenceEngine: inferenceEngine)
                }, handoffReanalysis: access.requestReanalysis.map { dispatch in { action in
                    guard viewModel.isPresentingLocalRecord(scanId: scanId, generation: generation),
                          case .identificationHistory(let activeID, let activeGeneration)? = activeShellPresentation,
                          activeID == scanId, activeGeneration == generation,
                          pendingHistoryReanalysis == nil else { return false }
                    pendingHistoryReanalysis = .init(scanID: scanId, generation: generation, action: action, dispatch: dispatch)
                    dismissActiveShellPresentation()
                    return true
                } }, publicationContinuation: publicationContinuation)
                if !requestShellPresentation(.identificationHistory(scanId: scanId, generation: generation)) {
                    historyModel?.close(); historyModel = nil
                }
            } catch { viewModel.state.toastMessage = .error("Identification history is unavailable right now.") }
        }
    }

    func resumeHistoryReanalysis(scanID: String, generation: UInt64) {
        let pending = pendingHistoryReanalysis
        pendingHistoryReanalysis = nil
        guard let pending, pending.scanID == scanID, pending.generation == generation else { return }
        do {
            try pending.resume { id, generation in viewModel.isPresentingLocalRecord(scanId: id, generation: generation) }
        } catch {
            viewModel.state.toastMessage = .error("This scan changed. Open history again before reanalyzing.")
        }
    }
}
