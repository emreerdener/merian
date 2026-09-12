enum HistoricalSyncPolicy {
    /// Scan rows fetched per cloud-history page.
    static let scanPageSize = 200

    /// Collection rows fetched per cloud-history page.
    static let collectionPageSize = 100

    /// SwiftData save checkpoint interval during bulk scan ingestion.
    static let ingestCheckpointInterval = 100
}
