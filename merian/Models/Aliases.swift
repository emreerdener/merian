import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV15.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV15.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV15.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV15.PendingCloudDeletionTask
