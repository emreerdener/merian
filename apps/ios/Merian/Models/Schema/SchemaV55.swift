import SwiftData

/// Adds owner-private analysis storage without rewriting legacy projections.
enum MerianSchemaV55: VersionedSchema {
    static var versionIdentifier = Schema.Version(55, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV55.LocalScanRecord.self, MerianSchemaV55.LocalAnalysisRecord.self, MerianSchemaV55.OfflineQueuedScan.self,
         MerianSchemaV55.CapturedMediaEntry.self, MerianSchemaV55.ScanCollection.self, MerianSchemaV55.PendingCloudDeletionTask.self,
         MerianSchemaV55.UserSpeciesPreference.self, MerianSchemaV55.OfflineJobRecord.self, MerianSchemaV55.OfflineQueueEvent.self,
         MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self]
    }
}
