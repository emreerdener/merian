import SwiftData

/// Persisted queue qualification prevents damaged payloads entering ordinary identification.
enum MerianSchemaV58: VersionedSchema {
    static var versionIdentifier = Schema.Version(58, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV58.LocalScanRecord.self, MerianSchemaV58.LocalAnalysisRecord.self, MerianSchemaV58.LocalAnalysisStateRecord.self,
         MerianSchemaV58.OfflineQueuedScan.self, MerianSchemaV58.CapturedMediaEntry.self, MerianSchemaV58.ScanCollection.self,
         MerianSchemaV58.PendingCloudDeletionTask.self, MerianSchemaV58.UserSpeciesPreference.self, MerianSchemaV58.OfflineJobRecord.self,
         MerianSchemaV58.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
