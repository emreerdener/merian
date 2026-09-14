import Foundation

/// Owns the engine's non-observable active scan identity plus the current task,
/// retained displaced task handles, and generation state for one foreground
/// inference presentation. Durable queue mutations are delegated to a narrow
/// service.
///
/// The engine remains the observable presentation facade;
/// `InferenceSessionLifecycleCoordinator` sequences cross-owner replacement,
/// and `InferencePresentationState` contains the stored presentation values.
/// Relinquished local ownership always clears before its durable callback so
/// synchronous callbacks cannot observe a displaced slot. A callback may
/// install a replacement without losing the old handle required by Auth
/// quiescence.
@MainActor
final class InferenceLiveAttemptCoordinator {
    private(set) var task: Task<Void, Error>?
    private(set) var activeScanId: String?
    private(set) var activeAttemptGeneration: UUID?
    private(set) var activeForegroundGeneration: UUID?
    private(set) var recoverablePresentationScanId: String?
    private var displacedTasks: [UUID: Task<Void, Error>] = [:]
    private var displacedTaskWaiters: [UUID: Task<Void, Never>] = [:]
    private var followUpAuthorizationGeneration: UInt64 = 0
    private var activeFollowUpAuthorizationGeneration: UInt64?

    private let queueService: InferenceLiveQueueService

    init(queueService: InferenceLiveQueueService) {
        self.queueService = queueService
    }

    func replaceTask(_ task: Task<Void, Error>?) {
        self.task = task
    }

    func cancelCurrentTask() {
        task?.cancel()
    }

    func cancelAllTasks() {
        task?.cancel()
        for displacedTask in displacedTasks.values {
            displacedTask.cancel()
        }
    }

    func awaitQuiescence() async {
        _ = await task?.result
        while !displacedTaskWaiters.isEmpty {
            let waiters = Array(displacedTaskWaiters.values)
            for waiter in waiters {
                await waiter.value
            }
        }
    }

    func clearCurrentTask() {
        task = nil
    }

    /// Relinquishes the exact local task and attempt without changing durable
    /// queue ownership. Recovery commits use this before publication so a
    /// synchronous observer can install a replacement without that replacement
    /// being cancelled by later caller cleanup.
    func cancelAndClearActiveAttempt() {
        let displacedTask = task
        task = nil
        clearActiveAttempt()
        if let displacedTask {
            retainUntilCompletion(displacedTask)
            displacedTask.cancel()
        }
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
        activeFollowUpAuthorizationGeneration =
            followUpAuthorizationGeneration
    }

    private func clearActiveAttempt() {
        activeScanId = nil
        activeAttemptGeneration = nil
        activeForegroundGeneration = nil
        activeFollowUpAuthorizationGeneration = nil
    }

    /// Closes accepted-result authority without releasing or retiring the
    /// durable queue owner. Auth admission uses this narrower fence because a
    /// full attempt invalidation would restart queue work during quiescence.
    func invalidateFollowUpAuthorization() {
        followUpAuthorizationGeneration &+= 1
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

    func canAuthorizeFollowUps(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundGeneration: UUID?
    ) -> Bool {
        activeFollowUpAuthorizationGeneration ==
            followUpAuthorizationGeneration &&
            isAttemptCurrent(
                scanId: scanId,
                attemptGeneration: attemptGeneration,
                foregroundGeneration: foregroundGeneration
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

    /// Atomically relinquishes the local attempt and its exact task before
    /// invoking durable queue callbacks. A callback may synchronously admit a
    /// replacement; detaching the displaced task first prevents later cleanup
    /// from cancelling that replacement.
    func invalidateActiveAttempt(
        resumeBackground: Bool,
        reason: String
    ) {
        let scanId = activeScanId
        let foregroundGeneration = activeForegroundGeneration
        cancelAndClearActiveAttempt()
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
            guard !Task.isCancelled,
                  followUpAuthorizationIsCurrent,
                  isLocalAttemptCurrent(
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

    private var followUpAuthorizationIsCurrent: Bool {
        activeFollowUpAuthorizationGeneration ==
            followUpAuthorizationGeneration
    }

    private func retainUntilCompletion(_ displacedTask: Task<Void, Error>) {
        let id = UUID()
        displacedTasks[id] = displacedTask
        displacedTaskWaiters[id] = Task { @MainActor [weak self] in
            _ = await displacedTask.result
            self?.displacedTasks[id] = nil
            self?.displacedTaskWaiters[id] = nil
        }
    }
}
