import SwiftUI

extension InsightSheetView {
    var confidenceReviewControls: ConfidenceReviewControls {
        let scanID = viewModel.presentedLocalRecordScanId
        let generation = viewModel.scanBoundActionGeneration
        let undo = undoReviewAction(scanID: scanID, generation: generation)
        let review = inferenceEngine.speciesData?.aiReview ?? .init()
        let protectedMessage = scanID.flatMap { permitsLegacyReview($0) ? nil
            : selectedReviewHost.model?.message ?? selectedReviewHost.message
                ?? (selectedReviewHost.model == nil ? "Identification review is unavailable. Reopen this scan to refresh it." : nil) }
        let confirm = inferenceEngine.speciesData?.canConfirmReanalysisProposal == true
            ? confirmReviewAction(scanID: scanID, generation: generation) : nil
        let reason = protectedMessage ?? selectedReviewHost.model?.confirmationUndoMessage ?? IdentificationReviewNotice.unavailableReason(review)
            ?? (review.state == .awaitingAcceptance && confirm == nil
                ? "This proposal cannot be accepted here. Review its identification or ask the community." : nil)
        let confirmationState = selectedReviewHost.model.flatMap { ConfidenceReviewControls.ConfirmationState.resolve($0.ticket) }
        let confirmationReason = protectedMessage ?? selectedReviewHost.model?.confirmationUndoMessage
            ?? (confirmationState != nil ? selectedReviewHost.message ?? "Undo confirmation is unavailable. Open this identification again to refresh its review." : nil)
        return ConfidenceReviewControls(confirmationState: confirmationState, undo: undo,
            undoConfirmation: undoConfirmationAction(scanID: scanID, generation: generation),
            undoConfirmationRequiresPrompt: selectedReviewHost.model?.confirmationUndo?.action == .name,
            confirmationUndoReason: undoConfirmationAction(scanID: scanID, generation: generation) == nil ? confirmationReason : nil,
            confirmProposal: confirm, unavailableReason: undo == nil ? reason : nil)
    }

    func undoConfirmationAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID, !permitsLegacyReview(scanID), let undo = selectedReviewHost.model?.confirmationUndo else { return nil }
        return protectedReviewAction(.undoConfirmation(confirmationOperationID: undo.operationID), scanID: scanID, generation: generation)
    }

    func confirmReviewAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID else { return nil }
        if !permitsLegacyReview(scanID) {
            if selectedReviewHost.model?.ticket.canConfirmPrimary == true {
                return protectedReviewAction(.confirmPrimary, scanID: scanID, generation: generation)
            }
            return namedReviewAction(scanID: scanID, generation: generation)
        }
        guard viewModel.canConfirm, let expectedReview = inferenceEngine.speciesData?.aiReview else { return nil }
        let isCurrent = {
            viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation) && permitsLegacyReview(scanID)
                && inferenceEngine.speciesData?.aiReview == expectedReview
                && (expectedReview.state == .awaitingAcceptance
                    ? inferenceEngine.speciesData?.canConfirmReanalysisProposal == true : viewModel.canConfirm)
        }
        return {
            guard isCurrent() else { return }
            dependencies.successFeedback()
            Task { @MainActor in
                guard isCurrent() else { return }
                await inferenceEngine.confirmAIIdentification(expectedScanId: scanID, modelContext: modelContext, expectedReview: expectedReview)
            }
        }
    }

    func incorrectReviewAction(scanID: String?, generation: UInt64) -> (() -> Void)? {
        guard let scanID else { return nil }
        if !permitsLegacyReview(scanID) {
            guard selectedReviewHost.model?.ticket.canReject == true else { return nil }
            return protectedReviewAction(.reject, scanID: scanID, generation: generation)
        }
        guard viewModel.canMarkIncorrect, let expectedReview = inferenceEngine.speciesData?.aiReview else { return nil }
        return {
            Task { @MainActor in
                guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation),
                      inferenceEngine.speciesData?.aiReview == expectedReview,
                      permitsLegacyReview(scanID), viewModel.canMarkIncorrect else { return }
                await inferenceEngine.markIdentificationIncorrect(expectedScanId: scanID, modelContext: modelContext, expectedReview: expectedReview, onLocalSave: {
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
        guard viewModel.canUndoIncorrect, let expectedReview = inferenceEngine.speciesData?.aiReview else { return nil }
        return {
            Task { @MainActor in
                guard viewModel.isPresentingLocalRecord(scanId: scanID, generation: generation),
                      inferenceEngine.speciesData?.aiReview == expectedReview,
                      permitsLegacyReview(scanID), viewModel.canUndoIncorrect else { return }
                viewModel.state.toastMessage = nil; viewModel.toastAction = nil
                await inferenceEngine.undoIncorrectIdentification(expectedScanId: scanID, modelContext: modelContext, expectedReview: expectedReview, onLocalSave: {
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
