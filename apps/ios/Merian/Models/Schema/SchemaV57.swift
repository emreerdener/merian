import SwiftData

/// Additive owner-private authority and display cache; existing selections stay intact.
enum MerianSchemaV57: VersionedSchema {
    static var versionIdentifier = Schema.Version(57, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV57.LocalScanRecord.self, MerianSchemaV57.LocalAnalysisRecord.self, MerianSchemaV57.LocalAnalysisStateRecord.self,
         MerianSchemaV57.OfflineQueuedScan.self, MerianSchemaV57.CapturedMediaEntry.self, MerianSchemaV57.ScanCollection.self,
         MerianSchemaV57.PendingCloudDeletionTask.self, MerianSchemaV57.UserSpeciesPreference.self, MerianSchemaV57.OfflineJobRecord.self,
         MerianSchemaV57.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
