import SwiftData

// MARK: - Active Schema Aliases
/// Single source of truth for the current schema version. When bumping to a new schema version,
/// update all four aliases here — no other call sites need to change.
typealias LocalScanRecord          = MerianSchemaV13.LocalScanRecord
typealias OfflineQueuedScan        = MerianSchemaV13.OfflineQueuedScan
typealias ScanCollection           = MerianSchemaV13.ScanCollection
typealias PendingCloudDeletionTask = MerianSchemaV12.PendingCloudDeletionTask
