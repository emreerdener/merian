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

    var photoPickerSelectionLimit: Int {
        let freshAutomaticCapture = diContainer.appSettings.autoSubmitScans
            && stagedCapture.isEmpty && descriptionDraft.isEmpty && baseRefinementContext == nil
        return freshAutomaticCapture ? 1 : max(1, availableStagedCaptureSlots)
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

    /// Accepts only the completed recording belonging to the current draft operation.
    func stageFinishedAudio(from recorder: AudioCaptureManager, expectedPath: String) {
        guard recorder.audioFilePath == expectedPath else { return }
        // A repeated observer delivery must never delete an already-owned original.
        guard !draftOwnedFiles.contains(expectedPath) else {
            recorder.acknowledgeStagedRecording()
            return
        }
        guard let operation = audioDraftOperation,
              operation.id == recorder.recordingID,
              draftSession.contains(operation) else {
            if let operation = audioDraftOperation, operation.id == recorder.recordingID {
                completeDraftOperation(operation, succeeded: false)
                audioDraftOperation = nil
            }
            recorder.reset()
            return
        }
        guard hasAvailableStagedCaptureSlot else {
            revokeAutomaticSubmission()
            recorder.restoreSubmissionForReview()
            offlineToastMessage = .error("Recording couldn’t be added. Free a media slot, then try again.")
            return
        }
        stagedCapture.audios.append(StagedAudio(
            filePath: expectedPath, prefersBoostedPreview: recorder.boostRecordingPreview
        ))
        draftOwnedFiles.insert(expectedPath)
        audioDraftOperation = nil
        recorder.acknowledgeStagedRecording()
        completeDraftOperation(operation, succeeded: true)
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
