import SwiftData

/// Frozen outgoing V63; no receipt or ownership is inferred during migration.
enum MerianSchemaV63: VersionedSchema {
    static var versionIdentifier = Schema.Version(63, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV63.LocalScanRecord.self, MerianSchemaV63.LocalAnalysisRecord.self, MerianSchemaV63.LocalAnalysisStateRecord.self,
         MerianSchemaV63.OfflineQueuedScan.self, MerianSchemaV63.CapturedMediaEntry.self, MerianSchemaV63.ScanCollection.self,
         MerianSchemaV63.PendingCloudDeletionTask.self, MerianSchemaV63.UserSpeciesPreference.self, MerianSchemaV63.OfflineJobRecord.self,
         MerianSchemaV63.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV63.PhotoPreparationRecord.self, MerianSchemaV63.PhotoPreparationAsset.self,
         MerianSchemaV63.PhotoPreparationReference.self, MerianSchemaV63.PhotoPreparationLease.self,
         MerianSchemaV63.SharedMediaInventoryRecord.self, MerianSchemaV63.SharedMediaAllocationRecord.self, MerianSchemaV63.SharedMediaReferenceRecord.self, MerianSchemaV63.SharedMediaLeaseRecord.self,
         MerianSchemaV63.SharedMediaInboxSourceRecord.self, MerianSchemaV63.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV63.SharedMediaDerivativePairRecord.self, MerianSchemaV63.SharedMediaDerivativeWorkRecord.self, MerianSchemaV63.SharedMediaConsumerRecord.self,
         MerianSchemaV63.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV63.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV63.SharedMediaPendingMembershipRecord.self]
    }
    typealias PendingCloudDeletionTask = MerianSchemaV62.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV62.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV62.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV62.OfflineQueueEvent
    typealias PhotoPreparationAsset = MerianSchemaV62.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV62.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV62.PhotoPreparationLease
    typealias SharedMediaInventoryRecord = MerianSchemaV62.SharedMediaInventoryRecord
    typealias SharedMediaAllocationRecord = MerianSchemaV62.SharedMediaAllocationRecord
    typealias SharedMediaReferenceRecord = MerianSchemaV62.SharedMediaReferenceRecord
    typealias SharedMediaLeaseRecord = MerianSchemaV62.SharedMediaLeaseRecord
    typealias SharedMediaInboxSourceRecord = MerianSchemaV62.SharedMediaInboxSourceRecord
    typealias SharedMediaInboxHandoffRecord = MerianSchemaV62.SharedMediaInboxHandoffRecord
    typealias SharedMediaDerivativePairRecord = MerianSchemaV62.SharedMediaDerivativePairRecord
    typealias SharedMediaDerivativeWorkRecord = MerianSchemaV62.SharedMediaDerivativeWorkRecord
}
