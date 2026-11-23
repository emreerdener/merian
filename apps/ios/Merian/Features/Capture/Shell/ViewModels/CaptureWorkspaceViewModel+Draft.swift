import Foundation

extension CaptureWorkspaceViewModel {
    var isDraftMutationLocked: Bool {
        videoReviewCommitID != nil || reanalysisLoadTask != nil || reanalysisEditor?.isBusy == true || reanalysisEditor?.isFrozen == true
            || isQueueingStagedCapture || isCheckingScanAdmission || discardConfirmationGeneration != nil
            || nativePhotoImportTask != nil || nativePhotoDispositionTask != nil
            || isInitialDraftWorkActive || initialDraftSession?.frozenPlan != nil
            || initialDraftSession?.needsPreparationAbort == true || !initialDraftPendingSources.isEmpty
            || (nativePhotoDraftSession.map { !$0.canEdit } ?? (stagedCapture.nativePhotoDraft != nil))
    }

    var isDraftAccountCurrent: Bool {
        draftSession.allowsAccount(dependencies.submission.admission.accountID())
    }

    /// A real identity replacement retires old private staging. An unresolved
    /// fresh capture remains unowned; a same-account token refresh preserves it.
    func handleDraftAccountChange() {
        if initialDraftSession != nil || initialDraftPresentation != nil || initialDraftProducerResources != nil || hasInitialDraftLiability {
            if !isDraftAccountCurrent || initialDraftAuthGeneration != diContainer.supabaseManager.authSessionGeneration
                || dependencies.submission.admission.isLibraryAccessBlocked() {
                invalidateInitialDraftForAccountChange()
                return
            }
        }
        if let session = fieldNotesSession,
           session.accountID != dependencies.submission.admission.accountID() {
            invalidateFieldNotes(clearProgress: true)
        }
        if nativeRecoveryModel?.isCurrent == false || dependencies.submission.admission.isLibraryAccessBlocked() {
            dismissNativeRecovery()
        }
        guard !isDraftAccountCurrent else { return }
        retireMediaReview()
        cancelActiveCropTask()
        photoReviewCommit = nil
        if reanalysisEditor != nil {
            invalidateHistoryWorkspace()
            offlineToastMessage = .information("Reanalysis closed after the account changed. Saved work is retained.")
            return
        }
        if nativePhotoDraftSession != nil || stagedCapture.nativePhotoDraft != nil {
            nativePhotoImportTask?.cancel()
            nativePhotoDraftSession?.clearPrivatePreviews()
            clearNativePhotoPresentation()
            offlineToastMessage = .information("Your local photo draft is retained while account access is resolved.")
            return
        }
        if let access = activePhotoOriginalPreparation {
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
        reanalysisLoadTask == nil && reanalysisEditor?.isBusy != true
            && !isInitialDraftWorkActive && initialDraftPendingSources.isEmpty
            && !draftSession.hasUnresolvedWork && !isCapturing && !isVideoRecording
            && !isPreparingVideo && !isStagingRefinement
            && imageToCrop == nil && photoReviewCommit == nil && videoReviewCommitID == nil
            && discardConfirmationGeneration == nil && !isQueueingStagedCapture
    }

    var canSubmitDraft: Bool {
        canRetryInitialDraft || canRecoverInitialDraft || (isDraftReadyForSubmission && !isCheckingScanAdmission && stagedCapture.physicalItemCount > 0
            && (reanalysisEditor == nil || stagedCapture.physicalItemCount > 0)
            && nativePhotoImportTask == nil && nativePhotoDispositionTask == nil
            && (nativePhotoDraftSession.map { $0.canEdit || $0.prepared != nil } ?? true))
    }

    var photoPickerSelectionLimit: Int {
        let freshAutomaticCapture = !usesNativePhotoComposition && diContainer.appSettings.autoSubmitScans
            && stagedCapture.isEmpty && descriptionDraft.isEmpty && !isReanalyzing
        return freshAutomaticCapture ? 1 : max(1, availableStagedCaptureSlots)
    }

    func beginDraftOperation(nativePhoto: Bool = false) -> CaptureDraftSession.Operation? {
        guard nativePhoto || !usesNativePhotoComposition else { return nil }
        guard !areCaptureActionsBlocked, mediaReviewPresentationID == nil,
              !isFeaturePresentationAwaitingDismissal, !draftSession.hasUnresolvedWork else { return nil }
        if let access = activePhotoOriginalPreparation {
            guard dependencies.submission.admission.accountID() == access.owner.account.ownerID,
                  !dependencies.submission.admission.isLibraryAccessBlocked() else { return nil }
        }
        guard bindDraftToCurrentAccount() else { return nil }
        automaticPreferenceRevision = diContainer.appSettings.autoSubmitRevision
        return draftSession.begin(
            autoSubmit: !usesNativePhotoComposition && diContainer.appSettings.autoSubmitScans,
            compositionIsEmpty: stagedCapture.isEmpty && descriptionDraft.isEmpty,
            isRefining: isReanalyzing
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
            if !beginAutomaticStagedSubmissionIfEligible(), !preservingRestoredContext {
                if let latest = stagedCapture.orderedNodes.last(where: {
                    if case .description = $0 { return false }
                    return true
                }) { _ = presentMediaReview(nodeID: latest.id) }
            }
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
        if usesInitialDraftComposition {
            stageInitialRecording(from: recorder, expectedPath: expectedPath, operation: operation)
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
        if isReviewActive || !stagedCapture.isEmpty || isReanalyzing {
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
            if isReanalyzing {
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
        guard !isFieldNotesOccupied, photoReviewCommit == nil,
              !isQueueingStagedCapture, !isCheckingScanAdmission else { return }
        guard !isInitialDraftWorkActive else { return }
        if nativePhotoDraftSession != nil || stagedCapture.nativePhotoDraft != nil {
            guard nativePhotoDraftSession?.canDiscard == true, !draftSession.hasUnresolvedWork,
                  nativePhotoImportTask == nil, nativePhotoDispositionTask == nil else { return }
        }
        discardConfirmationGeneration = draftSession.generation
    }

    @discardableResult
    func confirmDraftDiscard(generation: UUID) -> Bool {
        guard generation == draftSession.generation,
              !isInitialDraftWorkActive,
              !isFieldNotesOccupied, photoReviewCommit == nil,
              !isQueueingStagedCapture, !isCheckingScanAdmission else { return false }
        if nativePhotoDraftSession != nil || stagedCapture.nativePhotoDraft != nil {
            guard nativePhotoDraftSession?.canDiscard == true, !draftSession.hasUnresolvedWork,
                  nativePhotoImportTask == nil, nativePhotoDispositionTask == nil else { return false }
        }
        discardConfirmationGeneration = nil
        if initialDraftSession != nil { discardInitialDraft(); return true }
        if reanalysisEditor != nil { return discardHistoryWorkspace() }
        restoreRefinementInsightAfterCancellation()
        clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
        cancelRefinementStaging()
        return true
    }

    func isProspectiveFreeMediaEligible(images: Int = 0, audio: Int = 0) -> Bool {
        guard !isReanalyzing else { return false }
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
