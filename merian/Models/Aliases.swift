import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV19.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV19.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV19.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV19.PendingCloudDeletionTask
