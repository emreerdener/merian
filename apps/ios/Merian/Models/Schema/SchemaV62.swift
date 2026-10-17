import SwiftData

/// Frozen outgoing V62; no ownership is inferred during migration.
enum MerianSchemaV62: VersionedSchema {
    static var versionIdentifier = Schema.Version(62, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV62.LocalScanRecord.self, MerianSchemaV62.LocalAnalysisRecord.self, MerianSchemaV62.LocalAnalysisStateRecord.self,
         MerianSchemaV62.OfflineQueuedScan.self, MerianSchemaV62.CapturedMediaEntry.self, MerianSchemaV62.ScanCollection.self,
         MerianSchemaV62.PendingCloudDeletionTask.self, MerianSchemaV62.UserSpeciesPreference.self, MerianSchemaV62.OfflineJobRecord.self,
         MerianSchemaV62.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV62.PhotoPreparationRecord.self, MerianSchemaV62.PhotoPreparationAsset.self,
         MerianSchemaV62.PhotoPreparationReference.self, MerianSchemaV62.PhotoPreparationLease.self,
         MerianSchemaV62.SharedMediaInventoryRecord.self, MerianSchemaV62.SharedMediaAllocationRecord.self, MerianSchemaV62.SharedMediaReferenceRecord.self, MerianSchemaV62.SharedMediaLeaseRecord.self,
         MerianSchemaV62.SharedMediaInboxSourceRecord.self, MerianSchemaV62.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV62.SharedMediaDerivativePairRecord.self, MerianSchemaV62.SharedMediaDerivativeWorkRecord.self]
    }
    typealias PendingCloudDeletionTask = MerianSchemaV61.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV61.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV61.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV61.OfflineQueueEvent
    typealias PhotoPreparationAsset = MerianSchemaV61.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV61.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV61.PhotoPreparationLease
    typealias SharedMediaInventoryRecord = MerianSchemaV61.SharedMediaInventoryRecord
    typealias SharedMediaAllocationRecord = MerianSchemaV61.SharedMediaAllocationRecord
    typealias SharedMediaReferenceRecord = MerianSchemaV61.SharedMediaReferenceRecord
    typealias SharedMediaLeaseRecord = MerianSchemaV61.SharedMediaLeaseRecord
    typealias SharedMediaInboxSourceRecord = MerianSchemaV61.SharedMediaInboxSourceRecord
    typealias SharedMediaInboxHandoffRecord = MerianSchemaV61.SharedMediaInboxHandoffRecord
}
