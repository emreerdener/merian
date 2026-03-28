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

    /// Lossy compression quality applied to WebP-encoded captures before storage or upload.
    /// 0.85 preserves fine morphological detail (feather barbs, insect wing venation, leaf
    /// margins) relevant to species identification. File size increase over 0.80 is ~10–15%
    /// and stays well within the 5 MB payload limit.
    /// Passed as `kCGImageDestinationLossyCompressionQuality` to `CGImageDestination`.
    static let imageCompressionQuality: CGFloat = 0.85

    /// Longest-edge pixel cap for images sent to the AI inference pipeline.
    /// 1024 px is sufficient for Gemini species identification and keeps the base64
    /// payload small (~100-250 KB), reducing token cost and upload latency.
    static let inferenceImageMaxSize: CGFloat = 1024

    /// Longest-edge pixel cap for images written to disk and shown in the insight sheet
    /// and scan library. 2048 px covers the full-width pixel density of the largest
    /// current iPhone (Pro Max 3× → 1290 px) and iPad Pro (2× → 2048 px) without
    /// upscaling. Stored as WebP; files average ~300–700 KB vs ~100–250 KB at inference quality.
    static let displayImageMaxSize: CGFloat = 2048

    // MARK: - AI Confidence Bands

    /// Defines the UX threshold boundaries for AI confidence scores.
    struct ConfidenceBands {
        /// Minimum score for the green "Strong match" UI.
        let strong: Double
        /// Minimum score for the orange "Possible match" UI. Below this is a "Weak match".
        let possible: Double
        /// The threshold below which the Diagnostic Comparison (Lookalike) UI is triggered.
        let diagnosticTrigger: Double
    }
    
    /// Gemini 2.5 Flash (Free Tier)
    /// Flash is fast but can be overconfident on edge cases. We enforce stricter
    /// thresholds here to ensure we don't confidently misidentify lookalikes.
    static let flashConfidence = ConfidenceBands(
        strong: 0.96,             // Require higher certainty for the green badge
        possible: 0.75,
        diagnosticTrigger: 0.88   // Trigger the diagnostic lookalike UI more frequently
    )
    
    /// Gemini 2.5 Pro (Premium Tier)
    /// Pro is a deep reasoning engine. It is more cautious and better calibrated.
    /// An 85% from Pro is highly trustworthy, so we relax the UI thresholds to 
    /// reward the premium user with a more decisive experience.
    static let proConfidence = ConfidenceBands(
        strong: 0.85,             // Trust the model's rigorous evaluation
        possible: 0.65,
        diagnosticTrigger: 0.80   // Only trigger diagnostics on truly ambiguous scans
    )
    
    /// Helper to grab the correct bands based on the active user's entitlement.
    static func confidenceBands(for isPro: Bool) -> ConfidenceBands {
        return isPro ? proConfidence : flashConfidence
    }

    // MARK: - On-Device Vision Classification

    /// Minimum Vision confidence score for an observation to drive subject-specific scan phrases.
    static let visionConfidenceThreshold: Float = 0.65

    /// Minimum confidence margin the top Vision observation must lead the second-best by.
    /// Split or ambiguous results (e.g. 0.52 bird / 0.48 plant) stay on the generic phrase series.
    static let visionMarginThreshold: Float = 0.15

    // MARK: - Scanning Phase UX Timing

    /// How long to display the generic scan phrases before switching to subject-specific ones.
    /// Ensures the generic series always plays through the opening of a scan and reduces the
    /// chance of an incorrect category label being visible if Vision misclassifies early frames.
    static let scanningPhaseSubjectDelayNs: UInt64 = 1_500_000_000   // 1.5 s (was 3.0 s)
    /// Pause between consecutive subject-specific phase phrases during an active scan.
    static let scanningPhaseRotationIntervalNs: UInt64 = 2_300_000_000 // 2.3 s
}
