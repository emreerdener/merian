import SwiftData

/// Persisted queue qualification prevents damaged payloads entering ordinary identification.
enum MerianSchemaV58: VersionedSchema {
    static var versionIdentifier = Schema.Version(58, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, LocalAnalysisRecord.self, LocalAnalysisStateRecord.self,
         OfflineQueuedScan.self, CapturedMediaEntry.self, ScanCollection.self,
         PendingCloudDeletionTask.self, UserSpeciesPreference.self, OfflineJobRecord.self,
         OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
