import SwiftData
import SwiftUI

extension InsightSheetView {
    func startSavedReanalysis(scanID: String, generation: UInt64) {
        guard let access = dependencies.savedReanalysisAccess, savedReanalysisTask == nil,
              viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation),
              let record = viewModel.activeLocalRecord, record.id.caseInsensitiveCompare(scanID) == .orderedSame,
              let observation = UUID(uuidString: scanID) else { return }
        do {
            // Freeze the displayed correction synchronously, before the first suspension.
            let displayed = ObservationHistoryStateSyncService.ReviewBaseline(record, displayAnalysisID: observation)
            let request = try access.prepare(scanID, displayed, modelContext.container)
            let token = UUID()
            savedReanalysisTaskID = token
            dependencies.selectionFeedback()
            savedReanalysisTask = Task { @MainActor in
                defer {
                    if savedReanalysisTaskID == token { savedReanalysisTask = nil; savedReanalysisTaskID = nil }
                }
                do {
                    let action = try await request.resolve()
                    try Task.checkCancellation()
                    guard savedReanalysisTaskID == token,
                          viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation) else { return }
                    access.dispatch(try action.resolve())
                } catch {
                    guard !Task.isCancelled, savedReanalysisTaskID == token,
                          viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation) else { return }
                    viewModel.state.toastMessage = .error("Reanalysis couldn’t be opened. Your identification is unchanged. Try again.")
                }
            }
        } catch {
            viewModel.state.toastMessage = .error("This scan changed or is unavailable. Reopen it before reanalyzing.")
        }
    }

    func cancelSavedReanalysis() {
        savedReanalysisTask?.cancel(); savedReanalysisTask = nil; savedReanalysisTaskID = nil
    }
}
