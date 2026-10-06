import SwiftUI

extension InsightSheetView {
    /// Actual tap owns the loaded baseline; protected failure never enters legacy chat.
    func openProtectedChat(_ baseline: SelectedAnalysisReviewBaseline?, scanID: String,
                           generation: UInt64, engineGeneration: UInt64) {
        guard activeShellPresentation == nil, dismissedShellPresentation == nil, pendingShellPresentation == nil,
              let baseline, baseline.observationID.uuidString.caseInsensitiveCompare(scanID) == .orderedSame,
              viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation),
              inferenceEngine.scanPresentationGeneration == engineGeneration,
              viewModel.toolbarRecordSnapshot?.selectedReviewBaseline == baseline,
              let access = dependencies.protectedChatAccess else {
            viewModel.state.toastMessage = .information("Field chat is unavailable for this identification. Reopen the scan to refresh it.")
            return
        }
        do {
            let session = try access.open(baseline, modelContext.container)
            let vm = viewModel, engine = inferenceEngine
            protectedChatContinuation.bind(session.ticket, container: ObjectIdentifier(modelContext.container))
            let model = ProtectedInsightChatModel(baseline: baseline, session: session, continuation: protectedChatContinuation,
                presentationIsCurrent: {
                    vm.isPresentingLocalRecord(scanId: scanID, generation: generation)
                        && engine.scanPresentationGeneration == engineGeneration
                })
            protectedChatModel = model
            guard requestShellPresentation(.protectedChat(token: model.id, scanId: scanID, generation: generation)) else {
                model.close(); protectedChatModel = nil; return
            }
            dependencies.sheetFeedback()
        } catch {
            viewModel.state.toastMessage = .information("Field chat is unavailable for this identification. Reopen the scan to refresh it.")
        }
    }
    func closeProtectedChat(clearContinuation: Bool = false) {
        protectedChatModel?.close()
        cancelOrDismissShellPresentation { if case .protectedChat = $0 { true } else { false } }
        if clearContinuation { protectedChatContinuation.clear() }
    }
}
