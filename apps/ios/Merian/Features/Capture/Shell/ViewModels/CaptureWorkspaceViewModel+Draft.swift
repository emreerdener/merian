import Foundation

extension CaptureWorkspaceViewModel {
    var isDraftMutationLocked: Bool {
        isQueueingStagedCapture || isCheckingScanAdmission || discardConfirmationGeneration != nil
    }

    /// Also used after admission, when the admission lock is already held.
    var isDraftReadyForSubmission: Bool {
        !draftSession.hasUnresolvedWork && !isCapturing && !isVideoRecording
            && !isPreparingVideo && !isStagingRefinement
            && !hasPendingRequiredGalleryCrop && imageToCrop == nil
            && discardConfirmationGeneration == nil && !isQueueingStagedCapture
    }

    var canSubmitDraft: Bool {
        isDraftReadyForSubmission && !isCheckingScanAdmission && !stagedCapture.isEmpty
    }

    func beginDraftOperation() -> CaptureDraftSession.Operation? {
        guard !isDraftMutationLocked, !draftSession.hasUnresolvedWork else { return nil }
        automaticPreferenceRevision = diContainer.appSettings.autoSubmitRevision
        return draftSession.begin(
            autoSubmit: diContainer.appSettings.autoSubmitScans,
            compositionIsEmpty: stagedCapture.isEmpty && descriptionDraft.isEmpty,
            isRefining: baseRefinementContext != nil
        )
    }

    func completeDraftOperation(_ operation: CaptureDraftSession.Operation, succeeded: Bool) {
        guard draftSession.finish(operation, succeeded: succeeded) else { return }
        if succeeded {
            isReviewActive = true
            synchronizeSharedDescription()
            beginAutomaticStagedSubmissionIfEligible()
        } else {
            finishAutomaticStagedSubmissionAttempt()
        }
    }

    func reconcileEndedAudioOperation(isRecording: Bool, hasPendingReview: Bool, hasSubmittedAudio: Bool) {
        guard !isRecording, !hasPendingReview, !hasSubmittedAudio,
              let operation = audioDraftOperation else { return }
        completeDraftOperation(operation, succeeded: false)
        audioDraftOperation = nil
    }

    func updateDescriptionDraft(_ context: ObservationContext) {
        guard !isDraftMutationLocked else { return }
        descriptionDraft = context
        revokeAutomaticSubmission()
        if isReviewActive || !stagedCapture.isEmpty || baseRefinementContext != nil {
            synchronizeSharedDescription()
        }
        resetReviewIfEmpty()
    }

    func resetReviewIfEmpty() {
        if stagedCapture.isEmpty && descriptionDraft.isEmpty { isReviewActive = false }
    }

    func synchronizeSharedDescription() {
        if descriptionDraft.isEmpty {
            if baseRefinementContext != nil {
                if let index = stagedCapture.refinementSupplementIndex {
                    stagedCapture.observationContexts.remove(at: index)
                }
            } else {
                stagedCapture.observationContexts.removeAll()
            }
        } else {
            _ = stagePendingDescribeDraftForActiveSubmission(descriptionDraft)
        }
    }

    func revokeAutomaticSubmission() {
        draftSession.revokeAutomaticSubmission()
        finishAutomaticStagedSubmissionAttempt()
    }

    func requestDraftDiscard() {
        guard !isQueueingStagedCapture, !isCheckingScanAdmission else { return }
        discardConfirmationGeneration = draftSession.generation
    }

    @discardableResult
    func confirmDraftDiscard(generation: UUID) -> Bool {
        guard generation == draftSession.generation,
              !isQueueingStagedCapture, !isCheckingScanAdmission else { return false }
        discardConfirmationGeneration = nil
        restoreRefinementInsightAfterCancellation()
        clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
        cancelRefinementStaging()
        return true
    }

    func isProspectiveFreeMediaEligible(images: Int = 0, audio: Int = 0) -> Bool {
        guard baseRefinementContext == nil else { return false }
        return IdentificationEvidenceAllowance.permitsFreeScan(
            images: stagedCapture.images.count + images,
            audio: stagedCapture.audios.count + audio,
            descriptions: max(stagedCapture.observationContexts.count, descriptionDraft.isEmpty ? 0 : 1),
            videos: stagedCapture.videos.count
        )
    }
}
