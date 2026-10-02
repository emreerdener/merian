import SwiftData

/// Adds independent owner rejection authority and pending review intent.
enum MerianSchemaV54: VersionedSchema {
    static var versionIdentifier = Schema.Version(54, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self, UserSpeciesPreference.self,
         OfflineJobRecord.self, OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
