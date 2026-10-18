import SwiftData

/// Additive acquisition receipts; migration never adopts files or activates a producer.
enum MerianSchemaV64: VersionedSchema {
    static var versionIdentifier = Schema.Version(64, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LocalScanRecord.self, LocalAnalysisRecord.self, LocalAnalysisStateRecord.self,
         OfflineQueuedScan.self, CapturedMediaEntry.self, ScanCollection.self,
         PendingCloudDeletionTask.self, UserSpeciesPreference.self, OfflineJobRecord.self,
         OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         PhotoPreparationRecord.self, PhotoPreparationAsset.self,
         PhotoPreparationReference.self, PhotoPreparationLease.self,
         SharedMediaInventoryRecord.self, SharedMediaAllocationRecord.self, SharedMediaReferenceRecord.self, SharedMediaLeaseRecord.self,
         SharedMediaInboxSourceRecord.self, SharedMediaInboxHandoffRecord.self,
         SharedMediaDerivativePairRecord.self, SharedMediaDerivativeWorkRecord.self, SharedMediaConsumerRecord.self,
         SharedMediaAssetReferenceCountRecord.self, SharedMediaMembershipBootstrapRecord.self, SharedMediaPendingMembershipRecord.self, SharedMediaAcquisitionReceiptRecord.self]
    }
}
