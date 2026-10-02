import SwiftData

/// Adds the immutable AI primary answer and separate confirmed-identity storage.
enum MerianSchemaV53: VersionedSchema {
    static var versionIdentifier = Schema.Version(53, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV53.LocalScanRecord.self, MerianSchemaV53.OfflineQueuedScan.self, MerianSchemaV53.CapturedMediaEntry.self,
         MerianSchemaV53.ScanCollection.self, MerianSchemaV53.PendingCloudDeletionTask.self,
         MerianSchemaV53.UserSpeciesPreference.self, MerianSchemaV53.OfflineJobRecord.self, MerianSchemaV53.OfflineQueueEvent.self,
         MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
