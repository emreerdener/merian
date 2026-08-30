import SwiftUI

extension CaptureWorkspaceViewModel {
    func messageShareCacheSignature(
        records: [LocalScanRecord],
        defaultGeoprivacy: String
    ) -> String {
        CaptureWorkspacePresentationPolicy.messageShareCacheSignature(
            records: records,
            defaultGeoprivacy: defaultGeoprivacy,
            sharedPostId: dependencies.sharedExplorePostId
        )
    }

    func captureGoalAccountId(for userId: UUID?) -> String? {
        dependencies.captureGoalAccountId(userId)
    }

    func triggerSelectionFeedback(source: String) {
        dependencies.feedback.selection(source)
    }

    func triggerSheetFeedback(source: String? = nil) {
        dependencies.feedback.sheet(source)
    }

    func triggerMediumFeedback() {
        dependencies.feedback.medium()
    }

    func triggerErrorFeedback() {
        dependencies.feedback.error()
    }

    // MARK: - Notification Suppression Context

    /// Updates the global notification suppression flag used by PushNotificationManager.
    /// Informs the OS whether the user is actively engaged with the live scan UI.
    func updateNotificationSuppression() {
        // Suppress if the user is looking at the final insight sheet.
        let isActivelyWatchingScan = activeSheet == .insight
        diContainer.appSettings.suppressInferenceBanners = isActivelyWatchingScan
    }

    func validateEnvironmentContextPermissions() {
        diContainer.environmentContextManager.validatePermissions()
    }

    func startLiveEnvironmentContextTracking() {
        diContainer.environmentContextManager.startLiveLocationTracking()
    }

    func stopLiveEnvironmentContextTracking() {
        diContainer.environmentContextManager.stopLiveLocationTracking()
    }

    // MARK: - Workspace State Coordination

    func handleScenePhaseChange(
        _ newPhase: ScenePhase,
        captureMode: CaptureMode,
        cameraManager: CameraManager,
        audioCaptureManager: AudioCaptureManager
    ) {
        if newPhase == .active {
            if captureMode == .visual,
               self.activeSheet == nil,
               self.imageToCrop == nil {
                cameraManager.startSession()
            }
        }
        if newPhase == .inactive || newPhase == .background {
            handleVisualCaptureInterruption()
            audioCaptureManager.cancelPendingRecordingTransition()
            if audioCaptureManager.isRecording && !audioCaptureManager.isPaused {
                audioCaptureManager.pauseRecording()
            }
        }
        if newPhase == .background {
            diContainer.offlineQueueManager.releaseAllDeferredLiveUploads(
                reason: "app_backgrounded"
            )
            diContainer.offlineQueueManager.releaseAllForegroundInferenceClaims(
                reason: "app_backgrounded"
            )
        }
    }

    func handleCaptureModeChange(
        _ newMode: CaptureMode,
        scenePhase: ScenePhase,
        cameraManager: CameraManager,
        audioCaptureManager: AudioCaptureManager
    ) {
        triggerSheetFeedback()

        if newMode != .audio {
            audioCaptureManager.cancelPendingRecordingTransition()
            if audioCaptureManager.isRecording && !audioCaptureManager.isPaused {
                audioCaptureManager.pauseRecording()
            }
        }
        if newMode != .visual {
            handleVisualCaptureInterruption()
        }

        if newMode == .audio || newMode == .describe {
            cameraManager.stopSession()
        } else if scenePhase == .active,
                  self.activeSheet == nil,
                  self.imageToCrop == nil {
            cameraManager.startSession()
        }
    }
}
