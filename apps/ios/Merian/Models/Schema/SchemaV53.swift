import SwiftData

/// Adds the immutable AI primary answer and separate confirmed-identity storage.
enum MerianSchemaV53: VersionedSchema {
    static var versionIdentifier = Schema.Version(53, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, OfflineQueuedScan.self, CapturedMediaEntry.self,
         ScanCollection.self, PendingCloudDeletionTask.self,
         UserSpeciesPreference.self, OfflineJobRecord.self, OfflineQueueEvent.self,
         MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
