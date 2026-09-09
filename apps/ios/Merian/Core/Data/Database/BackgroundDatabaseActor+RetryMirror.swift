/// Actor-isolated retry-mirror mutation shared by serialized upload and
/// inference transitions. Keeping this as a `BackgroundDatabaseActor`
/// extension prevents callers from mutating SwiftData queue models outside the
/// owning actor.
extension BackgroundDatabaseActor {
    /// Reconciles the two durable copies of retry ownership before a queue
    /// transition mutates either model.
    ///
    /// Real migrated stores can temporarily expose a stale scalar snapshot in
    /// one SwiftData context after another context commits. The monotonic
    /// counter and high-authority cloud-recovery markers must therefore heal
    /// from either copy instead of trusting only the queue row.
    @discardableResult
    func reconcileMirroredInferenceState(
        scan: OfflineQueuedScan,
        job: OfflineJobRecord
    ) -> Int {
        let attempt = max(
            0,
            max(scan.queueAttemptCount, job.attemptCount)
        )
        scan.queueAttemptCount = attempt
        job.attemptCount = attempt

        let hasCompletedCloudResult =
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                scan.queueLastErrorCode
            ) ||
            OfflineQueueManager.isCompletedServerResultRecoveryCode(
                job.lastErrorCode
            )
        if hasCompletedCloudResult {
            scan.queueLastErrorCode =
                OfflineQueueManager.completedServerResultRecoveryCode
            scan.queueLastErrorMessage =
                OfflineQueueManager.completedServerResultRecoveryMessage
            job.lastErrorCode =
                OfflineQueueManager.completedServerResultRecoveryCode
            job.lastErrorMessage =
                OfflineQueueManager.completedServerResultRecoveryMessage
        } else if OfflineQueueManager.isServerRetryableFailureCode(
            scan.queueLastErrorCode
        ) || OfflineQueueManager.isServerRetryableFailureCode(
            job.lastErrorCode
        ) {
            let retryMessage = OfflineQueueManager
                .isServerRetryableFailureCode(scan.queueLastErrorCode)
                ? (scan.queueLastErrorMessage ?? job.lastErrorMessage)
                : (job.lastErrorMessage ?? scan.queueLastErrorMessage)
            scan.queueLastErrorCode =
                OfflineQueueManager.serverRetryableFailureCode
            scan.queueLastErrorMessage = retryMessage
            job.lastErrorCode =
                OfflineQueueManager.serverRetryableFailureCode
            job.lastErrorMessage = retryMessage
        }
        return attempt
    }
}
