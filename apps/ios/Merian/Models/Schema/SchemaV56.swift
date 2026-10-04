import SwiftData

/// Preserves unknown completion dates for imported saved identifications.
enum MerianSchemaV56: VersionedSchema {
    static var versionIdentifier = Schema.Version(56, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV56.LocalScanRecord.self, MerianSchemaV56.LocalAnalysisRecord.self, MerianSchemaV56.OfflineQueuedScan.self,
         MerianSchemaV56.CapturedMediaEntry.self, MerianSchemaV56.ScanCollection.self, MerianSchemaV56.PendingCloudDeletionTask.self,
         MerianSchemaV56.UserSpeciesPreference.self, MerianSchemaV56.OfflineJobRecord.self, MerianSchemaV56.OfflineQueueEvent.self,
         MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
