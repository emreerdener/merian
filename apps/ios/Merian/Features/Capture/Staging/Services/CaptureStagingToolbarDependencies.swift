import Photos

struct CaptureStagingToolbarDependencies {
    let photoLibrary: PHPhotoLibrary
    let dismissKeyboard: @MainActor @Sendable () -> Void
    let performCancelFeedback: @MainActor @Sendable () -> Void
    let hasShownTooltip: @MainActor @Sendable () -> Bool
    let markTooltipShown: @MainActor @Sendable () -> Void

    @MainActor
    static func live(diContainer: AppDIContainer) -> Self {
        Self(
            photoLibrary: PHPhotoLibrary.shared(),
            dismissKeyboard: {
                CaptureWorkspaceKeyboardService.dismissKeyboard()
            },
            performCancelFeedback: {
                diContainer.hapticManager.triggerMediumPulse(
                    source: "capture.staged.cancel"
                )
            },
            hasShownTooltip: {
                CaptureStagingToolbarSessionState.hasShownTooltip
            },
            markTooltipShown: {
                CaptureStagingToolbarSessionState.hasShownTooltip = true
            }
        )
    }
}

@MainActor
private enum CaptureStagingToolbarSessionState {
    static var hasShownTooltip = false
}
