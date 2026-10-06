import SwiftUI

extension InsightSheetView {
    func confirmReviewAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID else { return nil }
        if !permitsLegacyReview(scanID) {
            guard selectedReviewHost.model?.ticket.canConfirmPrimary == true else { return nil }
            return protectedReviewAction(.confirmPrimary, scanID: scanID, generation: generation)
        }
        guard viewModel.canConfirm else { return nil }
        return {
            guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation), permitsLegacyReview(scanID) else { return }
            dependencies.successFeedback()
            Task { @MainActor in
                guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation), permitsLegacyReview(scanID) else { return }
                await inferenceEngine.confirmAIIdentification(expectedScanId: scanID, modelContext: modelContext)
            }
        }
    }

    func incorrectReviewAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID else { return nil }
        if !permitsLegacyReview(scanID) {
            guard selectedReviewHost.model?.ticket.canReject == true else { return nil }
            return protectedReviewAction(.reject, scanID: scanID, generation: generation)
        }
        guard viewModel.canMarkIncorrect else { return nil }
        return {
            Task { @MainActor in
                guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation),
                      permitsLegacyReview(scanID), viewModel.canMarkIncorrect else { return }
                await inferenceEngine.markIdentificationIncorrect(expectedScanId: scanID, modelContext: modelContext, onLocalSave: {
                    guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation), permitsLegacyReview(scanID) else { return }
                    viewModel.toastAction = undoReviewAction(scanID: scanID, generation: generation)
                    viewModel.state.toastMessage = .information("Marked as incorrect", action: .init(id: .undo, title: "Undo"))
                })
            }
        }
    }

    func undoReviewAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID else { return nil }
        if !permitsLegacyReview(scanID) {
            guard let operation = selectedReviewHost.model?.undoOperation else { return nil }
            return protectedReviewAction(.undo(rejectionOperationID: operation), scanID: scanID, generation: generation)
        }
        guard viewModel.canUndoIncorrect else { return nil }
        return {
            Task { @MainActor in
                guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation),
                      permitsLegacyReview(scanID), viewModel.canUndoIncorrect else { return }
                viewModel.state.toastMessage = nil; viewModel.toastAction = nil
                await inferenceEngine.undoIncorrectIdentification(expectedScanId: scanID, modelContext: modelContext, onLocalSave: {
                    guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation), permitsLegacyReview(scanID) else { return }
                    viewModel.state.toastMessage = .success("Incorrect mark undone")
                })
            }
        }
    }

    func alternativesReviewAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID, permitsLegacyReview(scanID), viewModel.canReviewAlternatives else { return nil }
        return {
            guard permitsLegacyReview(scanID) else { return }
            viewModel.presentCandidateSwipe(expectedScanId: scanID, expectedGeneration: generation)
        }
    }

    func retryReviewAction() -> (() -> Void)? {
        guard selectedReviewHost.model?.canRetrySave == true, let token = selectedReviewHost.token else { return nil }
        return { selectedReviewHost.retrySave(token: token) }
    }

    private func protectedReviewAction(_ decision: ObservationAnalysisReviewRequest.Decision,
                                       scanID: String, generation: UInt64) -> (() -> Void)? {
        guard selectedReviewHost.model?.canSubmit == true, let token = selectedReviewHost.token else { return nil }
        return {
            guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation), !permitsLegacyReview(scanID) else { return }
            // The host checks its retained binding token and exact displayed
            // ticket; submit persists synchronously before the queue wake.
            selectedReviewHost.submit(decision, token: token)
        }
    }
}
