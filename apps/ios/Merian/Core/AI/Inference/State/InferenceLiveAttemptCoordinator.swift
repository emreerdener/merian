import Foundation

/// Owns the engine's non-observable active scan identity plus the task and
/// generation state for one foreground inference presentation. Durable queue
/// mutations are delegated to a narrow service.
///
/// The engine remains the observable presentation and orchestration owner.
/// Relinquished local ownership always clears before its durable callback so
/// synchronous callbacks cannot observe or regain a displaced slot.
@MainActor
final class InferenceLiveAttemptCoordinator {
    private(set) var task: Task<Void, Error>?
    private(set) var activeScanId: String?
    private(set) var activeAttemptGeneration: UUID?
    private(set) var activeForegroundGeneration: UUID?
    private(set) var recoverablePresentationScanId: String?

    private let queueService: InferenceLiveQueueService

    init(queueService: InferenceLiveQueueService) {
        self.queueService = queueService
    }

    func replaceTask(_ task: Task<Void, Error>?) {
        self.task = task
    }

    func setActiveScanId(_ scanId: String?) {
        activeScanId = scanId
    }

    func setActiveAttemptGeneration(_ generation: UUID?) {
        activeAttemptGeneration = generation
    }

    func setActiveForegroundGeneration(_ generation: UUID?) {
        activeForegroundGeneration = generation
    }

    func setRecoverablePresentationScanId(_ scanId: String?) {
        recoverablePresentationScanId = scanId
    }

    func activate(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?
    ) {
        activeScanId = scanId
        activeAttemptGeneration = attemptGeneration
        activeForegroundGeneration = foregroundGeneration
    }

    func clearActiveAttempt() {
        activeScanId = nil
        activeAttemptGeneration = nil
        activeForegroundGeneration = nil
    }

    func clearActiveAttemptIfCurrent(
        scanId: String?,
        attemptGeneration: UUID
    ) -> Bool {
        guard isLocalAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration
        ) else {
            return false
        }
        clearActiveAttempt()
        return true
    }

    func isLocalAttemptCurrent(
        scanId: String?,
        attemptGeneration: UUID
    ) -> Bool {
        activeScanId == scanId &&
            activeAttemptGeneration == attemptGeneration
    }

    func isAttemptCurrent(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?
    ) -> Bool {
        guard isLocalAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration
        ) else {
            return false
        }
        guard let scanId, let foregroundGeneration else {
            return foregroundGeneration == nil
        }
        return queueService.isForegroundInferenceAttemptCurrent(
            scanId: scanId,
            generation: foregroundGeneration
        )
    }

    func checkAttempt(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?
    ) throws {
        try Task.checkCancellation()
        guard isAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration
        ) else {
            throw CancellationError()
        }
    }

    func isDuplicateActiveForegroundAttempt(
        scanId: String,
        generation: UUID
    ) -> Bool {
        activeScanId == scanId &&
            activeForegroundGeneration == generation &&
            activeAttemptGeneration != nil
    }

    func claimForegroundInferenceStart(
        scanId: String,
        generation: UUID
    ) -> Bool {
        queueService.claimForegroundInferenceStart(
            scanId: scanId,
            generation: generation
        )
    }

    func releaseDeferredUpload(
        scanId: String,
        foregroundGeneration: UUID?,
        reason: String
    ) {
        queueService.releaseDeferredUpload(
            scanId: scanId,
            foregroundGeneration: foregroundGeneration,
            reason: reason
        )
    }

    func retireForegroundInference(
        scanId: String,
        generation: UUID,
        resumeBackground: Bool,
        reason: String
    ) {
        queueService.retireForegroundInference(
            scanId: scanId,
            generation: generation,
            resumeBackground: resumeBackground,
            reason: reason
        )
    }

    func releaseAndRetire(
        scanId: String?,
        foregroundGeneration: UUID?,
        resumeBackground: Bool,
        reason: String
    ) {
        guard let scanId, let foregroundGeneration else { return }
        releaseDeferredUpload(
            scanId: scanId,
            foregroundGeneration: foregroundGeneration,
            reason: reason
        )
        retireForegroundInference(
            scanId: scanId,
            generation: foregroundGeneration,
            resumeBackground: resumeBackground,
            reason: reason
        )
    }

    func invalidateActiveAttempt(
        resumeBackground: Bool,
        reason: String
    ) {
        let scanId = activeScanId
        let foregroundGeneration = activeForegroundGeneration
        clearActiveAttempt()
        releaseAndRetire(
            scanId: scanId,
            foregroundGeneration: foregroundGeneration,
            resumeBackground: resumeBackground,
            reason: reason
        )
    }

    func retireForegroundInferenceIfCurrent(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?,
        resumeBackground: Bool,
        reason: String
    ) {
        guard let scanId, let foregroundGeneration,
              isLocalAttemptCurrent(
                  scanId: scanId,
                  attemptGeneration: attemptGeneration
              ), activeForegroundGeneration == foregroundGeneration else {
            return
        }

        // Retain the local scan/attempt until the caller publishes its queue
        // handoff or the task defer runs, but fence this durable owner before a
        // synchronous retirement callback can re-enter the coordinator.
        activeForegroundGeneration = nil
        retireForegroundInference(
            scanId: scanId,
            generation: foregroundGeneration,
            resumeBackground: resumeBackground,
            reason: reason
        )
    }

    /// A queue-less request must supply two nil identifiers. Queue-backed work
    /// succeeds only when deletion returns for the same complete local/durable
    /// tuple; a partial identity or any post-suspension replacement fails closed.
    func completeQueuedInferenceIfNeeded(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?,
        mediaPathsToKeep: [String]
    ) async -> Bool {
        guard let scanId, let foregroundGeneration else {
            return scanId == nil && foregroundGeneration == nil
        }

        let didDelete = await queueService.deleteQueuedScan(
            scanId: scanId,
            explicitlyAdoptedMediaPaths: mediaPathsToKeep,
            foregroundGeneration: foregroundGeneration
        )
        if didDelete {
            guard isLocalAttemptCurrent(
                scanId: scanId,
                attemptGeneration: attemptGeneration,
                foregroundGeneration: foregroundGeneration
            ) else {
                return false
            }
            activeForegroundGeneration = nil
            return true
        }

        retireForegroundInferenceIfCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundGeneration,
            resumeBackground: true,
            reason: "live_cleanup_failed_or_replaced"
        )
        return false
    }

    func canCommitRecoveredBackgroundResult(
        scanId: String,
        replacingAttemptGeneration: UUID,
        expectedForegroundGeneration: UUID?
    ) -> Bool {
        isLocalAttemptCurrent(
            scanId: scanId,
            attemptGeneration: replacingAttemptGeneration
        ) &&
            activeForegroundGeneration == expectedForegroundGeneration &&
            queueService.foregroundInferenceGeneration(for: scanId) == nil
    }

    func isDurableAttemptCurrent(
        scanId: String,
        generation: UUID
    ) -> Bool {
        queueService.isForegroundInferenceAttemptCurrent(
            scanId: scanId,
            generation: generation
        )
    }

    @discardableResult
    func rejectQueuedScan(
        scanId: String,
        reason: String,
        errorCode: String
    ) -> Bool {
        queueService.rejectQueuedScan(
            scanId: scanId,
            reason: reason,
            errorCode: errorCode
        )
    }

    private func isLocalAttemptCurrent(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?
    ) -> Bool {
        isLocalAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration
        ) && activeForegroundGeneration == foregroundGeneration
    }
}
