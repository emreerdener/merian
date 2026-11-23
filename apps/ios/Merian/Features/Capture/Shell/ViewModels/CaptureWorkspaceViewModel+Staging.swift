import Foundation

extension CaptureWorkspaceViewModel {
    // MARK: - Optional Media Review

    var shouldSuppressCaptureChromeForCrop: Bool {
        mediaReviewPresentationID != nil || imageToCrop != nil
    }

    var isAutomaticSubmissionArmed: Bool {
        !usesNativePhotoComposition && diContainer.appSettings.autoSubmitScans && draftSession.automaticAttempt != nil
            && !dependencies.submission.admission.isLibraryAccessBlocked()
            && draftSession.allowsAccount(dependencies.submission.admission.accountID())
            && automaticPreferenceRevision == diContainer.appSettings.autoSubmitRevision
    }

    var shouldAutoSubmitStagedCapture: Bool {
        isAutomaticSubmissionArmed && isDraftReadyForSubmission && !stagedCapture.isEmpty
    }

    var shouldPresentActiveScanToolbar: Bool {
        Self.shouldPresentActiveScanToolbar(
            hasStagedContent: !stagedCapture.isEmpty || hasInitialDraftLiability,
            isRefining: isReanalyzing,
            isAutomaticSubmissionPending: isAutomaticStagedSubmissionPending
        )
    }

    nonisolated static func shouldPresentActiveScanToolbar(
        hasStagedContent: Bool,
        isRefining: Bool,
        isAutomaticSubmissionPending: Bool
    ) -> Bool {
        guard !isAutomaticSubmissionPending else { return false }
        return hasStagedContent || isRefining
    }

    @discardableResult
    func beginAutomaticStagedSubmissionIfEligible() -> Bool {
        let shouldBegin = shouldAutoSubmitStagedCapture
        updateAutomaticStagedSubmissionPending(shouldBegin)
        return shouldBegin
    }

    func finishAutomaticStagedSubmissionAttempt() {
        draftSession.revokeAutomaticSubmission()
        updateAutomaticStagedSubmissionPending(false)
    }

    func clearStagedCaptureAndCropState(
        discardStagedMediaFiles: Bool = false,
        allowingPendingQueue: Bool = false
    ) {
        guard !isQueueingStagedCapture || allowingPendingQueue else { return }
        if initialDraftSession != nil || hasInitialDraftLiability {
            if discardStagedMediaFiles { discardInitialDraft() }
            return
        }
        if stagedCapture.nativePhotoDraft != nil || nativePhotoDraftSession != nil {
            if discardStagedMediaFiles { discardNativePhotoDraft() }
            return
        }
        if let access = activePhotoOriginalPreparation {
            if discardStagedMediaFiles { discardPhotoPreparationDraft(access) }
            return
        }
        cancelAllVisualCaptureWork()
        retireMediaReview()
        cancelActiveCropTask()
        photoReviewCommit = nil
        let discardedMediaPaths = discardStagedMediaFiles
            ? Array(draftOwnedFiles)
            : []
        // Clear media while automatic ownership is still active. Releasing the
        // presentation fence first would briefly make the retained item eligible
        // for ActiveScanToolbar during this synchronous reset.
        stagedCapture.clearAll()
        clearFieldNotesAfterFinalMediaRemoval()
        descriptionDraft = ObservationContext()
        descriptionFocusRequest = nil
        isReviewActive = false
        draftSession.reset()
        audioDraftOperation = nil
        draftOwnedFiles.removeAll()
        discardConfirmationGeneration = nil
        finishAutomaticStagedSubmissionAttempt()
        discardLocalMediaFiles(at: discardedMediaPaths)
        editingCropIndex = nil
        imageToCrop = nil
    }

    func removeStagedVideo(at index: Int) {
        guard !areCaptureActionsBlocked, stagedCapture.videos.indices.contains(index) else { return }
        if initialDraftSession != nil { removeInitialDraftItem(stagedCapture.videos[index].id); return }
        revokeAutomaticSubmission()
        let removedVideo = stagedCapture.videos.remove(at: index)
        clearFieldNotesAfterFinalMediaRemoval()
        resetReviewIfEmpty()
        discardLocalMediaFiles(
            at: [removedVideo.filePath, removedVideo.audioFilePath, removedVideo.originalFilePath].compactMap { $0 }
        )
    }

    func removeStagedAudio(at index: Int) {
        guard !areCaptureActionsBlocked, stagedCapture.audios.indices.contains(index) else { return }
        if initialDraftSession != nil { removeInitialDraftItem(stagedCapture.audios[index].id); return }
        revokeAutomaticSubmission()
        let removedAudio = stagedCapture.audios.remove(at: index)
        clearFieldNotesAfterFinalMediaRemoval()
        resetReviewIfEmpty()
        discardLocalMediaFiles(at: [removedAudio.filePath])
    }

    /// A refinement editor draft updates the same supplementary item as the tray.
    /// Saving or removing that item supersedes the draft so Analyze cannot undo the edit.
    func saveStagedDescription(
        at index: Int,
        text: String,
        pendingDraft: inout ObservationContext
    ) {
        guard !areCaptureActionsBlocked, stagedCapture.observationContexts.indices.contains(index) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeStagedDescription(at: index, pendingDraft: &pendingDraft)
            return
        }
        if isReanalyzing,
           stagedCapture.observationContexts[index].isRefinementSupplement {
            pendingDraft = ObservationContext()
        }
        stagedCapture.observationContexts[index].context.freeText = trimmed
        schedulePhotoPreparationPersistence()
    }

    func removeStagedDescription(at index: Int, pendingDraft: inout ObservationContext) {
        guard !areCaptureActionsBlocked, stagedCapture.observationContexts.indices.contains(index) else { return }
        let removed = stagedCapture.observationContexts.remove(at: index)
        schedulePhotoPreparationPersistence()
        resetReviewIfEmpty()
        if isReanalyzing, removed.isRefinementSupplement {
            pendingDraft = ObservationContext()
        }
    }

    func discardLocalMediaFiles(at paths: [String]) {
        let uniquePaths = Array(Set(paths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        guard !uniquePaths.isEmpty else { return }
        Task(priority: .utility) {
            await FileIOActor.shared.deleteFiles(at: uniquePaths)
        }
    }

    func presentCrop(for index: Int) {
        guard !areCaptureActionsBlocked, stagedCapture.images.indices.contains(index) else { return }
        revokeAutomaticSubmission()
        _ = presentMediaReview(nodeID: "img_\(stagedCapture.images[index].original.id)")
    }

    func replaceActiveCropTask(with task: Task<Void, Never>) {
        operationState.replaceActiveCropTask(with: task)
    }

    func cancelActiveCropTask() {
        operationState.cancelActiveCropTask()
    }
}
