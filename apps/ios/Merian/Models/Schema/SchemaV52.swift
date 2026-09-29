import SwiftData

/// Adds optional immutable identification execution metadata to saved results.
enum MerianSchemaV52: VersionedSchema {
    static var versionIdentifier = Schema.Version(52, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MerianSchemaV52.LocalScanRecord.self, MerianSchemaV52.OfflineQueuedScan.self, MerianSchemaV52.CapturedMediaEntry.self,
         MerianSchemaV52.ScanCollection.self, MerianSchemaV52.PendingCloudDeletionTask.self,
         MerianSchemaV52.UserSpeciesPreference.self, MerianSchemaV52.OfflineJobRecord.self, MerianSchemaV52.OfflineQueueEvent.self,
         MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
