import SwiftData
import SwiftUI

extension InsightSheetView {
    var savedReanalysisPreparation: SavedReanalysisPreparation? {
        guard dependencies.savedReanalysisAccess != nil else { return nil }
        let generation = viewModel.scanBoundActionGeneration
        return { scanID, engineGeneration in
            prepareSavedReanalysis(scanID: scanID, generation: generation, engineGeneration: engineGeneration)
        }
    }

    func startSavedReanalysis(scanID: String, generation: UInt64) {
        prepareSavedReanalysis(scanID: scanID, generation: generation).resume()
    }

    func prepareSavedReanalysis(scanID: String, generation: UInt64,
                                engineGeneration: UInt64? = nil) -> SavedReanalysisTicket {
        guard let access = dependencies.savedReanalysisAccess, !savedReanalysisHandoff.isBusy else { return .unavailable }
        let model = viewModel, engine = inferenceEngine
        let expectedEngineGeneration = engineGeneration ?? engine.scanPresentationGeneration
        let current = {
            model.isPresentingLocalRecord(scanId: scanID, generation: generation)
                && engine.scanPresentationGeneration == expectedEngineGeneration
                && engine.speciesData?.scanId?.caseInsensitiveCompare(scanID) == .orderedSame
        }
        guard current(), let record = model.activeLocalRecord,
              record.id.caseInsensitiveCompare(scanID) == .orderedSame,
              let observation = UUID(uuidString: scanID) else { return .unavailable }
        do {
            // Freeze at the actual tap, before a child sheet begins dismissing.
            let displayed = ObservationHistoryStateSyncService.ReviewBaseline(record, displayAnalysisID: observation)
            let request = try access.prepare(scanID, displayed, modelContext.container)
            dependencies.selectionFeedback()
            return savedReanalysisHandoff.prepare(request: request, isCurrent: current, dispatch: access.dispatch, failure: {
                model.state.toastMessage = .error("Reanalysis couldn’t be opened. Your identification is unchanged. Try again.")
            })
        } catch {
            model.state.toastMessage = .error("This scan changed or is unavailable. Reopen it before reanalyzing.")
            return .unavailable
        }
    }

    func cancelSavedReanalysis() {
        pendingChatReanalysis?.cancel()
        pendingChatReanalysis = nil
        savedReanalysisHandoff.cancel()
    }
}
