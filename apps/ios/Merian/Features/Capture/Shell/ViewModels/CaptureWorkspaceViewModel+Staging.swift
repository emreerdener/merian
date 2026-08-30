import Foundation

extension CaptureWorkspaceViewModel {
    // MARK: - Manual Crop Routing

    var hasPendingRequiredGalleryCrop: Bool {
        stagedCapture.images.contains { image in
            operationState.containsRequiredGalleryCrop(
                imageID: image.original.id
            )
        }
    }

    /// Required imports enter staging before their full-screen crop cover can
    /// animate on screen. Keep the capture controls hidden from that ownership
    /// transfer into the mounted cover so the staged Identify tray cannot
    /// appear in its first frame. The crop cover remains the only full-screen
    /// presentation owner; manual recrops use the presentation half of this
    /// nonblocking chrome policy as well.
    var shouldSuppressCaptureChromeForCrop: Bool {
        Self.shouldSuppressCaptureChromeForCrop(
            hasPendingRequiredGalleryCrop: hasPendingRequiredGalleryCrop,
            isCropPresented: imageToCrop != nil
        )
    }

    nonisolated static func shouldSuppressCaptureChromeForCrop(
        hasPendingRequiredGalleryCrop: Bool,
        isCropPresented: Bool
    ) -> Bool {
        hasPendingRequiredGalleryCrop || isCropPresented
    }

    var shouldAutoSubmitStagedCapture: Bool {
        guard !diContainer.appSettings.requiresScanConfirmation else { return false }

        let isMultiCapture = isMultiCaptureFunctionallyEnabled || baseRefinementContext != nil
        guard !isMultiCapture else { return false }

        let hasOtherModalities = !stagedCapture.observationContexts.isEmpty || !stagedCapture.audios.isEmpty
        guard !hasOtherModalities else { return false }

        return stagedCapture.images.count + stagedCapture.videos.count == 1 && !hasPendingRequiredGalleryCrop
    }

    var shouldPresentActiveScanToolbar: Bool {
        Self.shouldPresentActiveScanToolbar(
            hasStagedContent: !stagedCapture.isEmpty,
            isRefining: baseRefinementContext != nil,
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
        updateAutomaticStagedSubmissionPending(false)
    }

    func isRequiredGalleryCrop(_ imageID: UUID) -> Bool {
        operationState.containsRequiredGalleryCrop(imageID: imageID)
    }

    @discardableResult
    func completeRequiredGalleryCrop(for imageID: UUID) -> Bool {
        operationState.removeRequiredGalleryCrop(imageID: imageID)

        if hasPendingRequiredGalleryCrop {
            presentNextRequiredGalleryCrop()
            return false
        }

        return beginAutomaticStagedSubmissionIfEligible()
    }

    func cancelRequiredGalleryCrop(for imageID: UUID) {
        cancelActiveCropTask()
        operationState.removeRequiredGalleryCrop(imageID: imageID)
        if let editIndex = stagedCapture.images.firstIndex(where: { $0.original.id == imageID }) {
            stagedCapture.images.remove(at: editIndex)
        }
        editingCropIndex = nil
        imageToCrop = nil
        presentNextRequiredGalleryCrop()
    }

    func clearStagedCaptureAndCropState(discardStagedMediaFiles: Bool = false) {
        cancelAllVisualCaptureWork()
        cancelActiveCropTask()
        operationState.removeAllRequiredGalleryCrops()
        let discardedMediaPaths = discardStagedMediaFiles
            ? stagedCapture.discardableLocalMediaFilePaths
            : []
        // Clear media while automatic ownership is still active. Releasing the
        // presentation fence first would briefly make the retained item eligible
        // for ActiveScanToolbar during this synchronous reset.
        stagedCapture.clearAll()
        finishAutomaticStagedSubmissionAttempt()
        discardLocalMediaFiles(at: discardedMediaPaths)
        editingCropIndex = nil
        imageToCrop = nil
    }

    func removeStagedVideo(at index: Int) {
        guard stagedCapture.videos.indices.contains(index) else { return }
        let removedVideo = stagedCapture.videos.remove(at: index)
        discardLocalMediaFiles(
            at: [removedVideo.filePath, removedVideo.audioFilePath].compactMap { $0 }
        )
    }

    func removeStagedAudio(at index: Int) {
        guard stagedCapture.audios.indices.contains(index) else { return }
        let removedAudio = stagedCapture.audios.remove(at: index)
        discardLocalMediaFiles(at: [removedAudio.filePath])
    }

    func discardLocalMediaFiles(at paths: [String]) {
        let uniquePaths = Array(Set(paths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
        guard !uniquePaths.isEmpty else { return }
        Task(priority: .utility) {
            await FileIOActor.shared.deleteFiles(at: uniquePaths)
        }
    }

    func presentCrop(for index: Int) {
        guard index < stagedCapture.images.count else { return }
        self.editingCropIndex = index
        self.imageToCrop = stagedCapture.images[index].original
    }

    func presentNextRequiredGalleryCrop() {
        while let nextImageId = operationState.firstRequiredGalleryCropImageID() {
            if let nextIndex = stagedCapture.images.firstIndex(where: { $0.original.id == nextImageId }) {
                presentCrop(for: nextIndex)
                return
            }
            operationState.removeFirstRequiredGalleryCrop()
        }
    }

    func replaceActiveCropTask(with task: Task<Void, Never>) {
        operationState.replaceActiveCropTask(with: task)
    }

    func cancelActiveCropTask() {
        operationState.cancelActiveCropTask()
    }
}
