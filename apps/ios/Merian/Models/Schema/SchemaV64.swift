import SwiftData

/// Frozen outgoing V64; migration never infers intents, file ownership or activation.
enum MerianSchemaV64: VersionedSchema {
    static var versionIdentifier = Schema.Version(64, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV64.LocalScanRecord.self, MerianSchemaV64.LocalAnalysisRecord.self, MerianSchemaV64.LocalAnalysisStateRecord.self,
         MerianSchemaV64.OfflineQueuedScan.self, MerianSchemaV64.CapturedMediaEntry.self, MerianSchemaV64.ScanCollection.self,
         MerianSchemaV64.PendingCloudDeletionTask.self, MerianSchemaV64.UserSpeciesPreference.self, MerianSchemaV64.OfflineJobRecord.self,
         MerianSchemaV64.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV64.PhotoPreparationRecord.self, MerianSchemaV64.PhotoPreparationAsset.self,
         MerianSchemaV64.PhotoPreparationReference.self, MerianSchemaV64.PhotoPreparationLease.self,
         MerianSchemaV64.SharedMediaInventoryRecord.self, MerianSchemaV64.SharedMediaAllocationRecord.self, MerianSchemaV64.SharedMediaReferenceRecord.self, MerianSchemaV64.SharedMediaLeaseRecord.self,
         MerianSchemaV64.SharedMediaInboxSourceRecord.self, MerianSchemaV64.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV64.SharedMediaDerivativePairRecord.self, MerianSchemaV64.SharedMediaDerivativeWorkRecord.self, MerianSchemaV64.SharedMediaConsumerRecord.self,
         MerianSchemaV64.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV64.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV64.SharedMediaPendingMembershipRecord.self, MerianSchemaV64.SharedMediaAcquisitionReceiptRecord.self]
    }
    typealias PendingCloudDeletionTask = MerianSchemaV63.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV63.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV63.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV63.OfflineQueueEvent
    typealias PhotoPreparationRecord = MerianSchemaV63.PhotoPreparationRecord
    typealias PhotoPreparationAsset = MerianSchemaV63.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV63.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV63.PhotoPreparationLease
    typealias SharedMediaInventoryRecord = MerianSchemaV63.SharedMediaInventoryRecord
    typealias SharedMediaAllocationRecord = MerianSchemaV63.SharedMediaAllocationRecord
    typealias SharedMediaReferenceRecord = MerianSchemaV63.SharedMediaReferenceRecord
    typealias SharedMediaLeaseRecord = MerianSchemaV63.SharedMediaLeaseRecord
    typealias SharedMediaInboxSourceRecord = MerianSchemaV63.SharedMediaInboxSourceRecord
    typealias SharedMediaInboxHandoffRecord = MerianSchemaV63.SharedMediaInboxHandoffRecord
    typealias SharedMediaDerivativePairRecord = MerianSchemaV63.SharedMediaDerivativePairRecord
    typealias SharedMediaDerivativeWorkRecord = MerianSchemaV63.SharedMediaDerivativeWorkRecord
    typealias SharedMediaConsumerRecord = MerianSchemaV63.SharedMediaConsumerRecord
    typealias SharedMediaAssetReferenceCountRecord = MerianSchemaV63.SharedMediaAssetReferenceCountRecord
    typealias SharedMediaMembershipBootstrapRecord = MerianSchemaV63.SharedMediaMembershipBootstrapRecord
    typealias SharedMediaPendingMembershipRecord = MerianSchemaV63.SharedMediaPendingMembershipRecord
}
