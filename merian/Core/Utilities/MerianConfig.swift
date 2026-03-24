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

    // MARK: - Image Quality

    /// JPEG compression quality applied when downsampling captures before storage or upload.
    /// 0.8 balances file size against perceptible quality loss on modern iPhone sensors.
    static let jpegCompressionQuality: CGFloat = 0.8

    // MARK: - On-Device Vision Classification

    /// Minimum Vision confidence score for an observation to drive subject-specific scan phrases.
    static let visionConfidenceThreshold: Float = 0.65
    /// Minimum gap between the top two Vision observations required to trust the classification.
    /// Guards against ambiguous frames where two categories score similarly (e.g., plant vs. bird).
    static let visionConfidenceMargin: Float = 0.15

    // MARK: - Scanning Phase UX Timing

    /// How long to display the generic scan phrases before switching to subject-specific ones.
    /// Ensures the generic series always plays through the opening of a scan and reduces the
    /// chance of an incorrect category label being visible if Vision misclassifies early frames.
    static let scanningPhaseSubjectDelayNs: UInt64 = 3_000_000_000   // 3.0 s
    /// Pause between consecutive subject-specific phase phrases during an active scan.
    static let scanningPhaseRotationIntervalNs: UInt64 = 2_300_000_000 // 2.3 s
}
