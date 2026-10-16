import SwiftData

/// Frozen outgoing V60. Existing media ownership is never inferred by migration.
enum MerianSchemaV60: VersionedSchema {
    static var versionIdentifier = Schema.Version(60, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV60.LocalScanRecord.self, MerianSchemaV60.LocalAnalysisRecord.self, MerianSchemaV60.LocalAnalysisStateRecord.self,
         MerianSchemaV60.OfflineQueuedScan.self, MerianSchemaV60.CapturedMediaEntry.self, MerianSchemaV60.ScanCollection.self,
         MerianSchemaV60.PendingCloudDeletionTask.self, MerianSchemaV60.UserSpeciesPreference.self, MerianSchemaV60.OfflineJobRecord.self,
         MerianSchemaV60.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV60.PhotoPreparationRecord.self, MerianSchemaV60.PhotoPreparationAsset.self,
         MerianSchemaV60.PhotoPreparationReference.self, MerianSchemaV60.PhotoPreparationLease.self,
         MerianSchemaV60.SharedMediaInventoryRecord.self, MerianSchemaV60.SharedMediaAllocationRecord.self, MerianSchemaV60.SharedMediaReferenceRecord.self, MerianSchemaV60.SharedMediaLeaseRecord.self]
    }
    typealias LocalScanRecord = MerianSchemaV59.LocalScanRecord
    typealias LocalAnalysisRecord = MerianSchemaV59.LocalAnalysisRecord
    typealias LocalAnalysisStateRecord = MerianSchemaV59.LocalAnalysisStateRecord
    typealias OfflineQueuedScan = MerianSchemaV59.OfflineQueuedScan
    typealias CapturedMediaEntry = MerianSchemaV59.CapturedMediaEntry
    typealias ScanCollection = MerianSchemaV59.ScanCollection
    typealias PendingCloudDeletionTask = MerianSchemaV59.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV59.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV59.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV59.OfflineQueueEvent
    typealias PhotoPreparationRecord = MerianSchemaV59.PhotoPreparationRecord
    typealias PhotoPreparationAsset = MerianSchemaV59.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV59.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV59.PhotoPreparationLease
}
