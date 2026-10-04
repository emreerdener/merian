import SwiftData

/// Adds independent owner rejection authority and pending review intent.
enum MerianSchemaV54: VersionedSchema {
    static var versionIdentifier = Schema.Version(54, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV54.LocalScanRecord.self, MerianSchemaV54.OfflineQueuedScan.self, MerianSchemaV54.CapturedMediaEntry.self,
         MerianSchemaV54.ScanCollection.self, MerianSchemaV54.PendingCloudDeletionTask.self, MerianSchemaV54.UserSpeciesPreference.self,
         MerianSchemaV54.OfflineJobRecord.self, MerianSchemaV54.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
