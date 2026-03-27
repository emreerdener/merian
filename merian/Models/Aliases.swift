import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV16.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV16.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV16.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV16.PendingCloudDeletionTask
