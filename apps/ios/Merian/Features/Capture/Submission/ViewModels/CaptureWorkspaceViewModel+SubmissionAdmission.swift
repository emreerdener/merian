extension CaptureWorkspaceViewModel {
    /// Opening a picker promises no selection count. Admit its minimum useful
    /// selection so exhausted Pro funding can still use a remaining Free scan.
    func requestPhotoPickerEntryAdmission(maximumSelectionCount: Int) async -> Bool {
        guard maximumSelectionCount > 0 else { return false }
        return await requestImageImportEntryAdmission(prospectiveImageCount: 1)
    }

    /// Once selection is known, check its actual evidence before loading files.
    /// The caller registered this operation synchronously at selection time.
    func admitSelectedImageImport(imageCount: Int, operation: CaptureDraftSession.Operation) async -> Bool {
        guard imageCount > 0, imageCount <= availableStagedCaptureSlots,
              draftSession.contains(operation) else { return false }
        let route = await requestScanAdmission(
            flashFallbackEligible: isProspectiveFreeMediaEligible(images: imageCount)
        )
        return route != nil && !Task.isCancelled && draftSession.contains(operation)
            && imageCount <= availableStagedCaptureSlots
    }

    /// Gates image-selection and file-preparation work before the user enters
    /// the picker or crop flow. Submission still rechecks admission because the
    /// read-only preview does not reserve quota.
    func requestImageImportEntryAdmission(
        prospectiveImageCount: Int
    ) async -> Bool {
        guard prospectiveImageCount > 0,
              prospectiveImageCount <= availableStagedCaptureSlots,
              !isDraftMutationLocked,
              !draftSession.hasUnresolvedWork,
              activePresentation == nil,
              !isRootPresentationDismissing else {
            return false
        }

        let existingItemCount = stagedCapture.totalItemCount
        let isRefining = baseRefinementContext != nil
        isCheckingScanAdmission = true
        defer { isCheckingScanAdmission = false }

        let flashFallbackEligible = isProspectiveFreeMediaEligible(images: prospectiveImageCount)
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
        let draftGeneration = draftSession.generation
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
        guard !Task.isCancelled, draftSession.generation == draftGeneration else { return nil }

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
