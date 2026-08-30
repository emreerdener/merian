extension CaptureWorkspaceViewModel {
    /// Gates image-selection and file-preparation work before the user enters
    /// the picker or crop flow. Submission still rechecks admission because the
    /// read-only preview does not reserve quota.
    func requestImageImportEntryAdmission(
        prospectiveImageCount: Int
    ) async -> Bool {
        guard prospectiveImageCount > 0,
              prospectiveImageCount <= availableStagedCaptureSlots,
              !isCheckingScanAdmission,
              activePresentation == nil,
              !isRootPresentationDismissing else {
            return false
        }

        let existingItemCount = stagedCapture.totalItemCount
        let isRefining = baseRefinementContext != nil
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }

        let flashFallbackEligible = CaptureSubmissionPolicy
            .isImageImportFlashFallbackEligible(
                existingItemCount: existingItemCount,
                prospectiveImageCount: prospectiveImageCount,
                isRefining: isRefining
            )
        let route = await requestScanAdmission(
            flashFallbackEligible: flashFallbackEligible
        )
        guard route != nil,
              !Task.isCancelled,
              activePresentation == nil,
              !isRootPresentationDismissing,
              stagedCapture.totalItemCount == existingItemCount,
              (baseRefinementContext != nil) == isRefining,
              prospectiveImageCount <= availableStagedCaptureSlots else {
            return false
        }
        return true
    }

    /// Uses the local meter while offline or when the bounded caller-scoped
    /// preview proves transport is unavailable. Both fallbacks are queue-only;
    /// malformed, unauthorized, and server failures remain blocked. The
    /// Identify reservation remains authoritative.
    func requestScanAdmission(
        flashFallbackEligible: Bool
    ) async -> CaptureScanAdmissionRoute? {
        let admission = dependencies.submission.admission
        let canStartLocally = admission.canStartLocally(
            flashFallbackEligible
        )
        let isOnline = admission.isOnline()
        let previewResult: ScanAdmissionPreviewResult?
        if isOnline {
            previewResult = await admission.preview(flashFallbackEligible)
        } else {
            previewResult = nil
        }
        guard !Task.isCancelled else { return nil }

        switch CaptureScanAdmissionPolicy.resolve(
            isOnline: isOnline,
            canStartLocally: canStartLocally,
            previewResult: previewResult
        ) {
        case .proceed(let route):
            return route
        case .paywall:
            presentScanAdmissionPaywall()
            return nil
        case .retryRequired:
            offlineToastMessage = .error(
                "Unable to check scan availability. Please try again."
            )
            return nil
        }
    }

    private func presentScanAdmissionPaywall() {
        AppTelemetry.trackPaywallImpression()
        activeSheet = .paywall
    }
}
