import SwiftData
import SwiftUI

extension InsightSheetView {
    func historyAction(scanId: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanId, let access = dependencies.historyAccess,
              access.hasMultiple(scanId, modelContext.container) else { return nil }
        return {
            guard viewModel.isPresentingLocalRecord(scanId: scanId, generation: generation),
                  historyModel == nil,
                  access.hasMultiple(scanId, modelContext.container) else { return }
            do {
                let service = try access.open(scanId, modelContext.container)
                historyModel?.close()
                historyModel = IdentificationHistoryViewModel(dependencies: service, isPresented: {
                    viewModel.isPresentingLocalRecord(scanId: scanId, generation: generation)
                }, didAdmit: {
                    viewModel.refreshAcknowledgedHistory(scanId: scanId, generation: generation,
                        container: modelContext.container, inferenceEngine: inferenceEngine)
                })
                if !requestShellPresentation(.identificationHistory(scanId: scanId, generation: generation)) {
                    historyModel?.close(); historyModel = nil
                }
            } catch { viewModel.state.toastMessage = .error("Identification history is unavailable right now.") }
        }
    }
}
