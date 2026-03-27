import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV17.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV17.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV17.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV17.PendingCloudDeletionTask
