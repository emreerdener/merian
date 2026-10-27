import Foundation

extension CaptureWorkspaceViewModel {
    var canPresentNativeRecovery: Bool {
        dependencies.submission.nativeRecoveryFactory != nil
            && dependencies.submission.admission.accountID() != nil
            && !dependencies.submission.admission.isLibraryAccessBlocked()
            && activePresentation == nil && !isRootPresentationDismissing
            && !isCapturing && !isVideoRecording && !isPreparingVideo
            && !isQueueingStagedCapture && !isCheckingScanAdmission
            && nativePhotoImportTask == nil && nativePhotoDispositionTask == nil
            && imageToCrop == nil && !isStagingRefinement
    }

    func presentNativeRecovery() {
        guard canPresentNativeRecovery,
              let account = dependencies.submission.admission.accountID(),
              let model = dependencies.submission.nativeRecoveryFactory?(account),
              model.isCurrent else { return }
        nativeRecoveryModel = model
        activeSheet = .nativeRecovery
    }

    func dismissNativeRecovery() {
        nativeRecoveryModel?.close()
        nativeRecoveryModel = nil
        if activeSheet == .nativeRecovery { dismissActivePresentation() }
    }
}
