extension CaptureWorkspaceViewModel {
    /// Consumes the app-wide paywall intent at the root presentation boundary.
    /// If Insight is already open, `activeSheet` performs its normal ordered
    /// dismissal and mounts the paywall only after UIKit releases that slot.
    func handlePaywallPresentationRequest(isRequested: Bool) {
        guard isRequested else { return }
        diContainer.usageManager.showPaywall = false
        AppTelemetry.trackPaywallImpression()
        activeSheet = .paywall
    }

    /// Responds to changes in `InferenceEngine.isProcessing`.
    func handleInferenceProcessingChange(isStillProcessing: Bool) {
        guard !isStillProcessing else { return }
        if diContainer.inferenceEngine.speciesData?.scanId != nil,
           activeSheet != .insight {
            diContainer.appSettings.hasUnseenScan = true
            AppIconBadgeCoordinator.updateAppIconBadge()
        }
    }
}
