import Foundation

extension CaptureWorkspaceViewModel {
    var isDraftMutationLocked: Bool {
        isQueueingStagedCapture || isCheckingScanAdmission || discardConfirmationGeneration != nil
    }

    var isDraftAccountCurrent: Bool {
        draftSession.allowsAccount(dependencies.submission.admission.accountID())
    }

    /// A real identity replacement retires old private staging. An unresolved
    /// fresh capture remains unowned; a same-account token refresh preserves it.
    func handleDraftAccountChange() {
        guard !isDraftAccountCurrent else { return }
        if let access = dependencies.photoOriginalPreparation {
            Task { _ = await access.owner.invalidateAndAwaitForAccountTransition() }
            offlineToastMessage = .information("Your local photo draft is retained while account access is resolved.")
            return
        }
        diContainer.audioCaptureManager.reset()
        diContainer.speechManager.stopDictation()
        cancelRefinementStaging()
        clearStagedCaptureAndCropState(
            discardStagedMediaFiles: !isQueueingStagedCapture,
            allowingPendingQueue: true
        )
        baseRefinementContext = nil
        refinementSubjectId = nil
        selectedPhotoItems.removeAll()
        preFetchTask?.cancel()
        preFetchTask = nil
        offlineToastMessage = .information("Draft cleared after the account changed.")
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
        if let access = dependencies.photoOriginalPreparation {
            guard dependencies.submission.admission.accountID() == access.owner.account.ownerID,
                  !dependencies.submission.admission.isLibraryAccessBlocked() else { return nil }
        }
        guard bindDraftToCurrentAccount() else { return nil }
        automaticPreferenceRevision = diContainer.appSettings.autoSubmitRevision
        return draftSession.begin(
            autoSubmit: diContainer.appSettings.autoSubmitScans,
            compositionIsEmpty: stagedCapture.isEmpty && descriptionDraft.isEmpty,
            isRefining: baseRefinementContext != nil
        )
    }

    func completeDraftOperation(_ operation: CaptureDraftSession.Operation, succeeded: Bool, preservingRestoredContext: Bool = false) {
        guard draftSession.finish(operation, succeeded: succeeded) else { return }
        if succeeded {
            isReviewActive = true
            if !preservingRestoredContext { synchronizeSharedDescription() }
            if dependencies.submission.admission.isLibraryAccessBlocked() {
                revokeAutomaticSubmission()
                return
            }
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
              draftSession.contains(operation), isDraftAccountCurrent else {
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
        guard !isDraftMutationLocked, bindDraftToCurrentAccount() else { return }
        descriptionDraft = context
        revokeAutomaticSubmission()
        if isReviewActive || !stagedCapture.isEmpty || baseRefinementContext != nil {
            synchronizeSharedDescription()
        }
        schedulePhotoPreparationPersistence()
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

    func bindDraftToCurrentAccount() -> Bool {
        let admission = dependencies.submission.admission
        // A fresh subject captured during recovery belongs to no library yet,
        // even if the SDK currently holds a different account's credentials.
        if draftSession.ownership == .unowned, admission.isLibraryAccessBlocked() { return true }
        guard draftSession.bindAccount(admission.accountID()) else {
            revokeAutomaticSubmission()
            offlineToastMessage = .information("This draft belongs to another account. Restore it in Profile or discard the draft.")
            return false
        }
        return true
    }
}
