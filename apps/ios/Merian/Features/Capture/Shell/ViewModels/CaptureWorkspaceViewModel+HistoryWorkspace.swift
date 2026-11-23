import Foundation

extension CaptureWorkspaceViewModel {
    /// A History child never enters ordinary initial-photo persistence or the
    /// legacy replacement path. Editors and the visible toolbar remain shared.
    var activePhotoOriginalPreparation: CapturePhotoOriginalPreparationAccess? {
        reanalysisEditor == nil ? dependencies.photoOriginalPreparation : nil
    }

    var canEditHistoryWorkspace: Bool {
        reanalysisEditor?.canEdit == true && reanalysisLoadTask == nil
    }

    var canRetryHistoryWorkspace: Bool {
        reanalysisEditor?.isFrozen == true && reanalysisEditor?.canSubmit == true
            && isDraftReadyForSubmission && isDraftAccountCurrent && !isCheckingScanAdmission
    }

    @discardableResult
    func beginHistoryWorkspace(_ target: HistoricalReanalysisTarget) -> Bool {
        guard reanalysisEditor == nil, reanalysisLoadTask == nil, !hasInitialDraftLiability,
              baseRefinementContext == nil, stagedCapture.isEmpty, descriptionDraft.isEmpty,
              !isDraftMutationLocked, !draftSession.hasUnresolvedWork,
              !isCapturing, !isVideoRecording, !isPreparingVideo,
              imageToCrop == nil, nativePhotoDraftSession == nil,
              let access = dependencies.reanalysis,
              let container = diContainer.offlineQueueManager.modelContext?.container else { return false }
        do {
            let editor = try access.open(target, container)
            guard bindDraftToCurrentAccount() else { editor.invalidate(); return false }
            reanalysisEditor = editor
            revokeAutomaticSubmission()
            activeSheet = nil
            requestedCaptureMode = .visual
            let generation = draftSession.generation
            reanalysisLoadTask = Task { [weak self] in
                await editor.loadForWorkspace()
                guard let self, self.reanalysisEditor === editor else { await editor.discardUnclaimedWorkspaceMedia(); return }
                defer { self.reanalysisLoadTask = nil }
                guard !Task.isCancelled, self.draftSession.generation == generation,
                      self.isDraftAccountCurrent else { return }
                guard editor.phase == .editing else {
                    let message = editor.errorMessage ?? "This identification’s media could not be opened."
                    self.finishHistoryWorkspace(editor, discardFiles: false)
                    self.offlineToastMessage = .error(message)
                    return
                }
                self.stagedCapture = editor.capture
                self.draftOwnedFiles.formUnion(editor.capture.discardableLocalMediaFilePaths)
                self.descriptionDraft = ObservationContext()
                self.isReviewActive = true
            }
            return true
        } catch {
            offlineToastMessage = .error("This identification could not be opened for reanalysis. Your scan is unchanged.")
            return false
        }
    }

    func submitHistoryWorkspace() async {
        guard let editor = reanalysisEditor, canSubmitDraft, isDraftAccountCurrent else { return }
        // Retrying a frozen plan uses its original bytes and identity.
        if !editor.isFrozen, !editor.updateWorkspaceCapture(stagedCapture, ownedPaths: draftOwnedFiles) {
            offlineToastMessage = .error("This media composition cannot be submitted yet. Your staged content is retained.")
            return
        }
        await editor.submit()
        guard reanalysisEditor === editor else { return }
        if editor.phase == .submitted {
            finishHistoryWorkspace(editor, discardFiles: true)
        } else if let message = editor.errorMessage {
            offlineToastMessage = .error(message)
        }
    }

    @discardableResult
    func discardHistoryWorkspace() -> Bool {
        guard let editor = reanalysisEditor, reanalysisLoadTask == nil else { return false }
        let observationID = editor.observationID
        guard editor.discard() else {
            if let message = editor.errorMessage { offlineToastMessage = .error(message) }
            return false
        }
        clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
        reanalysisEditor = nil
        if let observationID { handleDeepLinkRoute(scanId: observationID.uuidString.lowercased()) }
        return true
    }

    func invalidateHistoryWorkspace() {
        guard let editor = reanalysisEditor else { return }
        reanalysisLoadTask?.cancel()
        reanalysisLoadTask = nil
        draftOwnedFiles.formUnion(editor.capture.discardableLocalMediaFilePaths)
        editor.invalidate()
        clearStagedCaptureAndCropState(discardStagedMediaFiles: !isQueueingStagedCapture, allowingPendingQueue: true)
        reanalysisEditor = nil
    }

    private func finishHistoryWorkspace(_ editor: CaptureReanalysisEditor, discardFiles: Bool) {
        let observationID = editor.observationID
        clearStagedCaptureAndCropState(discardStagedMediaFiles: discardFiles)
        editor.invalidate()
        reanalysisEditor = nil
        if let observationID { handleDeepLinkRoute(scanId: observationID.uuidString.lowercased()) }
    }
}
