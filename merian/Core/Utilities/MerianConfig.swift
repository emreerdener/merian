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
    /// 100 halves WAL flush frequency vs. the previous 50 — acceptable for initial syncs
    /// since a task kill rolls back at most one 100-record batch, not the entire sync.
    static let ingestCheckpointInterval = 100

    // MARK: - Image Quality

    /// Lossy compression quality applied to WebP-encoded captures before storage or upload.
    /// 0.85 preserves fine morphological detail (feather barbs, insect wing venation, leaf
    /// margins) relevant to species identification. File size increase over 0.80 is ~10–15%
    /// and stays well within the 5 MB payload limit.
    /// Passed as `kCGImageDestinationLossyCompressionQuality` to `CGImageDestination`.
    static let imageCompressionQuality: CGFloat = 0.85

    /// Longest-edge pixel cap for Pro tier inference payloads (gemini-2.5-pro).
    /// At 1024 px a square image tiles into four 768×768 Gemini vision tiles (~1032 input tokens).
    /// Full resolution is warranted for Pro: subspecies, fossils, and cultivars require fine
    /// morphological detail (feather barbs, gill spacing, lichen areolae) to discriminate.
    static let proInferenceImageMaxSize: CGFloat = 1024

    /// Longest-edge pixel cap for Flash tier inference payloads (gemini-2.5-flash, free).
    /// At 768 px a square image fits within a single Gemini vision tile (~258 input tokens) —
    /// a ~75% token reduction vs the Pro cap with negligible accuracy impact for
    /// common-species macro-feature identification (bark texture, wing pattern, leaf shape).
    static let flashInferenceImageMaxSize: CGFloat = 768

    /// Returns the appropriate inference image pixel cap for the user's active subscription tier.
    /// Call this at the capture-pipeline boundary where `isProActive` is already resolved.
    static func inferenceImageMaxSize(isProActive: Bool) -> CGFloat {
        return isProActive ? proInferenceImageMaxSize : flashInferenceImageMaxSize
    }

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
    ///
    /// **Server-side source of truth**: `supabase/functions/_shared/identify/thresholds.ts`
    /// — FLASH_STRONG, FLASH_POSSIBLE, FLASH_DIAGNOSTIC_TRIGGER.
    /// Any change here must be mirrored there, and vice versa.
    static let flashConfidence = ConfidenceBands(
        strong: 0.95,
        possible: 0.75,
        // Decoupled from `strong`: candidates are shown for every scan below 0.99,
        // including "Strong match" scans (0.95–0.99). Flash can be overconfident on
        // visually similar species; the escape hatch must survive high-confidence calls.
        diagnosticTrigger: 0.99
    )

    /// Gemini 2.5 Pro (Premium Tier)
    /// Pro is a deep reasoning engine. It is more cautious and better calibrated.
    /// An 85% from Pro is highly trustworthy, so we relax the UI thresholds to
    /// reward the premium user with a more decisive experience.
    ///
    /// **Server-side source of truth**: `supabase/functions/_shared/identify/thresholds.ts`
    /// — PRO_STRONG, PRO_POSSIBLE, PRO_DIAGNOSTIC_TRIGGER.
    /// Any change here must be mirrored there, and vice versa.
    static let proConfidence = ConfidenceBands(
        strong: 0.85,
        possible: 0.65,
        // Same rationale as Flash: candidates are suppressed only at ≥ 0.99.
        diagnosticTrigger: 0.99
    )
    
    /// Helper to grab the correct bands based on the exact inference model tier used.
    static func confidenceBands(forInferenceTier tier: String?) -> ConfidenceBands {
        return tier == "pro" ? proConfidence : flashConfidence
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
