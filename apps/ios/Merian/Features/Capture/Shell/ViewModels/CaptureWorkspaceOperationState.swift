import Foundation

@MainActor
final class CaptureWorkspaceOperationState {
    private var externalRouteSessionResetSuppressionDeadline: Date?
    private var externalImageImportTask: Task<Void, Never>?
    private var externalImageImportRetryRequested = false
    private var defersExternalImageImportAfterCurrentIteration = false
    private var resumesExternalImageImportAfterSheetDismissal = false
    private var slotBlockedExternalImportIDs = Set<UUID>()
    private var paywallPresentedExternalImportIDs = Set<UUID>()
    private var routeRequestIDBeingApplied: UUID?
    private var dismissingPresentation: CaptureWorkspaceViewModel.PresentedRoute?
    private var deferredRouteRequestID: UUID?
    private var pendingLocalSheet: CaptureWorkspaceViewModel.ActiveSheet?
    private var requiredGalleryCropImageIDs: [UUID] = []
    private var refinementStagingTask: Task<Void, Never>?
    private var activeCropTask: Task<Void, Never>?

    var isDismissingPresentation: Bool {
        dismissingPresentation != nil
    }

    var applyingRouteRequestID: UUID? {
        routeRequestIDBeingApplied
    }

    func protectExternalRoute(fromTimeoutUntil deadline: Date) {
        externalRouteSessionResetSuppressionDeadline = deadline
    }

    func consumeExternalRouteTimeoutProtection(now: Date) -> Bool {
        defer { externalRouteSessionResetSuppressionDeadline = nil }
        guard let deadline = externalRouteSessionResetSuppressionDeadline else {
            return false
        }
        return now <= deadline
    }

    func beginApplyingRoute(requestID: UUID) {
        routeRequestIDBeingApplied = requestID
    }

    func finishApplyingRoute() {
        routeRequestIDBeingApplied = nil
    }

    func beginDismissing(_ presentation: CaptureWorkspaceViewModel.PresentedRoute) {
        dismissingPresentation = presentation
    }

    func takeDismissedPresentation() -> CaptureWorkspaceViewModel.PresentedRoute? {
        defer { dismissingPresentation = nil }
        return dismissingPresentation
    }

    func deferRoute(requestID: UUID) {
        deferredRouteRequestID = requestID
    }

    func takeDeferredRouteRequestID() -> UUID? {
        defer { deferredRouteRequestID = nil }
        return deferredRouteRequestID
    }

    func queueLocalSheet(_ sheet: CaptureWorkspaceViewModel.ActiveSheet) {
        pendingLocalSheet = sheet
    }

    func takePendingLocalSheet() -> CaptureWorkspaceViewModel.ActiveSheet? {
        defer { pendingLocalSheet = nil }
        return pendingLocalSheet
    }

    func clearPendingRoutes() {
        deferredRouteRequestID = nil
        pendingLocalSheet = nil
    }

    func clearPendingLocalSheet() {
        pendingLocalSheet = nil
    }

    @discardableResult
    func beginExternalImageImport(
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Bool {
        guard !resumesExternalImageImportAfterSheetDismissal else {
            return false
        }
        guard externalImageImportTask == nil else {
            externalImageImportRetryRequested = true
            return false
        }

        externalImageImportRetryRequested = false
        externalImageImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.externalImageImportRetryRequested = false
                self.defersExternalImageImportAfterCurrentIteration = false
                await operation()

                let isWaitingForSheetDismissal =
                    self.defersExternalImageImportAfterCurrentIteration
                    && self.resumesExternalImageImportAfterSheetDismissal
                guard self.externalImageImportRetryRequested,
                      !isWaitingForSheetDismissal else {
                    break
                }
            }

            // The retry check and handle release execute in one MainActor turn.
            // A request cannot set the retry flag after the loop has decided to
            // finish but before the task becomes available again.
            self.externalImageImportTask = nil
        }
        return true
    }

    func deferExternalImageImportUntilSheetDismissal() {
        defersExternalImageImportAfterCurrentIteration = true
        resumesExternalImageImportAfterSheetDismissal = true
        externalImageImportRetryRequested = false
    }

    func takeExternalImageImportResumeRequest() -> Bool {
        defer { resumesExternalImageImportAfterSheetDismissal = false }
        return resumesExternalImageImportAfterSheetDismissal
    }

    func markExternalImportSlotBlockIfNeeded(for importID: UUID) -> Bool {
        slotBlockedExternalImportIDs.insert(importID).inserted
    }

    func markExternalImportPaywallIfNeeded(for importID: UUID) -> Bool {
        paywallPresentedExternalImportIDs.insert(importID).inserted
    }

    func clearExternalImportPresentationHistory(for importID: UUID) {
        slotBlockedExternalImportIDs.remove(importID)
        paywallPresentedExternalImportIDs.remove(importID)
    }

    func appendRequiredGalleryCrop(imageID: UUID) {
        requiredGalleryCropImageIDs.append(imageID)
    }

    func containsRequiredGalleryCrop(imageID: UUID) -> Bool {
        requiredGalleryCropImageIDs.contains(imageID)
    }

    func firstRequiredGalleryCropImageID() -> UUID? {
        requiredGalleryCropImageIDs.first
    }

    func removeRequiredGalleryCrop(imageID: UUID) {
        requiredGalleryCropImageIDs.removeAll { $0 == imageID }
    }

    func removeFirstRequiredGalleryCrop() {
        guard !requiredGalleryCropImageIDs.isEmpty else { return }
        requiredGalleryCropImageIDs.removeFirst()
    }

    func removeAllRequiredGalleryCrops() {
        requiredGalleryCropImageIDs.removeAll()
    }

    func setRefinementStagingTask(_ task: Task<Void, Never>) {
        refinementStagingTask = task
    }

    func cancelRefinementStagingTask() {
        refinementStagingTask?.cancel()
        refinementStagingTask = nil
    }

    func replaceActiveCropTask(with task: Task<Void, Never>) {
        activeCropTask?.cancel()
        activeCropTask = task
    }

    func cancelActiveCropTask() {
        activeCropTask?.cancel()
        activeCropTask = nil
    }
}
