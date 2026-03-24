import Foundation

// MARK: - App-Wide Configuration Constants

/// Single source of truth for magic numbers used across the Core/Data layer.
///
/// Centralising these prevents silent divergence when tuning thresholds and makes
/// policy decisions (retention windows, batch sizes, storage limits) self-documenting.
enum MerianConfig {

    // MARK: - Free Tier Retention

    /// The earliest a Free Tier scan can enter the archive rescue window (days before expiry).
    static let archiveRescueWindowStartDays = 80
    /// The latest a Free Tier scan will be evaluated for rescue (days before full expiry).
    static let archiveRescueWindowEndDays   = 88

    // MARK: - Storage

    /// Minimum free device storage (bytes) required before archive or rescue operations proceed.
    static let diskSpaceThreshold: Int64 = 500 * 1024 * 1024  // 500 MB

    // MARK: - Upload Batching

    /// Maximum number of scans dispatched to R2 staging in a single sync cycle.
    static let uploadBatchSize = 5
    /// Maximum number of pending `OfflineQueuedScan` records fetched per sync cycle.
    static let pendingScanFetchLimit = 50

    // MARK: - Historical Sync Pagination

    /// Number of scan records fetched per page during historical sync-down.
    static let historicalSyncPageSize = 200
    /// Number of collection records fetched per page during historical sync-down.
    static let collectionsSyncPageSize = 100

    // MARK: - Bulk Ingestion

    /// SwiftData save checkpoint interval during bulk historical scan ingestion.
    /// A checkpoint every N records caps maximum data loss if a background task is killed.
    static let ingestCheckpointInterval = 50
}
