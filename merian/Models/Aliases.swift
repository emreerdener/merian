import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV21.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV21.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV21.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV21.PendingCloudDeletionTask
