import SwiftData

/// Additive owner-private authority and display cache; existing selections stay intact.
enum MerianSchemaV57: VersionedSchema {
    static var versionIdentifier = Schema.Version(57, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, LocalAnalysisRecord.self, LocalAnalysisStateRecord.self,
         OfflineQueuedScan.self, CapturedMediaEntry.self, ScanCollection.self,
         PendingCloudDeletionTask.self, UserSpeciesPreference.self, OfflineJobRecord.self,
         OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
