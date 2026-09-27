import SwiftData

/// Adds optional immutable identification execution metadata to saved results.
enum MerianSchemaV52: VersionedSchema {
    static var versionIdentifier = Schema.Version(52, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self, OfflineJobRecord.self, OfflineQueueEvent.self,
         MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
