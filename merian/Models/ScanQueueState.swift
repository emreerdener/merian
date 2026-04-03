import Foundation

// MARK: - Scan Queue State

/// Exhaustive lifecycle states for an `OfflineQueuedScan` record.
///
/// Stored as a raw `Int` on `OfflineQueuedScan.scanStateRaw` so SwiftData `#Predicate`
/// can filter on it without computed-property limitations.
///
/// **Never reorder or reassign existing raw values** — they are persisted in SQLite
/// and used in `#Predicate` integer comparisons across the codebase.
/// The gap at raw value 4 is intentional (reserved).
enum ScanQueueState: Int, Sendable {
    /// Files written to the Documents directory; upload not yet dispatched.
    case pending     = 0
    /// Background URLSession upload task dispatched; waiting for R2 confirmation.
    case uploading   = 1
    /// All image files confirmed received by R2 staging (HTTP 200 on last upload).
    /// `stagedR2Keys` is populated at this transition.
    case staged      = 2
    /// Edge Function inference call in flight.
    /// Acts as a persistent distributed lock — only one pipeline can hold this state
    /// per scan. Transitioned atomically via `BackgroundDatabaseActor.tryClaimForInference`.
    case inferencing = 3
    // raw value 4 reserved
    /// Tombstoned: upload or inference permanently rejected, or user-deleted.
    /// Awaiting purge by `purgeSoftDeletedRecords()`.
    case failed      = 5
}
