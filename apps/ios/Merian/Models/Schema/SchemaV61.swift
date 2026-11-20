import SwiftData

/// Frozen outgoing V61. Derivative ownership is never inferred by migration.
enum MerianSchemaV61: VersionedSchema {
    static var versionIdentifier = Schema.Version(61, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV61.LocalScanRecord.self, MerianSchemaV61.LocalAnalysisRecord.self, MerianSchemaV61.LocalAnalysisStateRecord.self,
         MerianSchemaV61.OfflineQueuedScan.self, MerianSchemaV61.CapturedMediaEntry.self, MerianSchemaV61.ScanCollection.self,
         MerianSchemaV61.PendingCloudDeletionTask.self, MerianSchemaV61.UserSpeciesPreference.self, MerianSchemaV61.OfflineJobRecord.self,
         MerianSchemaV61.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV61.PhotoPreparationRecord.self, MerianSchemaV61.PhotoPreparationAsset.self,
         MerianSchemaV61.PhotoPreparationReference.self, MerianSchemaV61.PhotoPreparationLease.self,
         MerianSchemaV61.SharedMediaInventoryRecord.self, MerianSchemaV61.SharedMediaAllocationRecord.self, MerianSchemaV61.SharedMediaReferenceRecord.self, MerianSchemaV61.SharedMediaLeaseRecord.self,
         MerianSchemaV61.SharedMediaInboxSourceRecord.self, MerianSchemaV61.SharedMediaInboxHandoffRecord.self]
    }
    typealias LocalScanRecord = MerianSchemaV60.LocalScanRecord
    typealias LocalAnalysisRecord = MerianSchemaV60.LocalAnalysisRecord
    typealias LocalAnalysisStateRecord = MerianSchemaV60.LocalAnalysisStateRecord
    typealias OfflineQueuedScan = MerianSchemaV60.OfflineQueuedScan
    typealias CapturedMediaEntry = MerianSchemaV60.CapturedMediaEntry
    typealias ScanCollection = MerianSchemaV60.ScanCollection
    typealias PendingCloudDeletionTask = MerianSchemaV60.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV60.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV60.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV60.OfflineQueueEvent
    typealias PhotoPreparationRecord = MerianSchemaV60.PhotoPreparationRecord
    typealias PhotoPreparationAsset = MerianSchemaV60.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV60.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV60.PhotoPreparationLease
    typealias SharedMediaInventoryRecord = MerianSchemaV60.SharedMediaInventoryRecord
    typealias SharedMediaAllocationRecord = MerianSchemaV60.SharedMediaAllocationRecord
    typealias SharedMediaReferenceRecord = MerianSchemaV60.SharedMediaReferenceRecord
    typealias SharedMediaLeaseRecord = MerianSchemaV60.SharedMediaLeaseRecord
}
