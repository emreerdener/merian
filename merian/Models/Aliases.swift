import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV14.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV14.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV14.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV14.PendingCloudDeletionTask
