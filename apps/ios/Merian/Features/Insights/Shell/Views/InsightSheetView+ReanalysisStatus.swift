import SwiftData
import SwiftUI

extension InsightSheetView {
    func reanalysisStatusAction(scanId: String?, generation: UInt64) -> (() -> Void)? {
        _ = historyAvailabilityRevision
        guard let scanId, let access = dependencies.reanalysisStatusAccess,
              access.available(scanId, modelContext.container) else { return nil }
        return {
            guard viewModel.isPresentingLocalRecord(scanId: scanId, generation: generation),
                  reanalysisStatusModel == nil else { return }
            do {
                let service = try access.open(scanId, modelContext.container)
                reanalysisStatusModel = ReanalysisStatusViewModel(dependencies: service, isPresented: {
                    viewModel.isPresentingLocalRecord(scanId: scanId, generation: generation)
                })
                if !requestShellPresentation(.reanalysisStatus(scanId: scanId, generation: generation)) {
                    reanalysisStatusModel?.close(); reanalysisStatusModel = nil
                }
            } catch { viewModel.state.toastMessage = .error("Reanalysis status is unavailable right now.") }
        }
    }
}
