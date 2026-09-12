enum OfflineQueueBatchPolicy {
    /// Maximum scans dispatched to R2 staging in one sync cycle.
    static let uploadBatchSize = 5

    /// Maximum pending queue records fetched per sync cycle.
    static let pendingScanFetchLimit = 50
}
