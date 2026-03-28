import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV20.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV20.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV20.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV20.PendingCloudDeletionTask
