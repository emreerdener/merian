import SwiftData

/// Frozen outgoing V59 graph. No legacy operation is rewritten.
enum MerianSchemaV59: VersionedSchema {
    static var versionIdentifier = Schema.Version(59, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV59.LocalScanRecord.self, MerianSchemaV59.LocalAnalysisRecord.self, MerianSchemaV59.LocalAnalysisStateRecord.self,
         MerianSchemaV59.OfflineQueuedScan.self, MerianSchemaV59.CapturedMediaEntry.self, MerianSchemaV59.ScanCollection.self,
         MerianSchemaV59.PendingCloudDeletionTask.self, MerianSchemaV59.UserSpeciesPreference.self, MerianSchemaV59.OfflineJobRecord.self,
         MerianSchemaV59.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV59.PhotoPreparationRecord.self, MerianSchemaV59.PhotoPreparationAsset.self,
         MerianSchemaV59.PhotoPreparationReference.self, MerianSchemaV59.PhotoPreparationLease.self]
    }
}
