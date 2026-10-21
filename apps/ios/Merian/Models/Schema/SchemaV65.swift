import SwiftData

/// Additive receiving intent slots; migration creates no intents or authority.
enum MerianSchemaV65: VersionedSchema {
    static var versionIdentifier = Schema.Version(65, 0, 0)
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
         SharedMediaAssetReferenceCountRecord.self, SharedMediaMembershipBootstrapRecord.self, SharedMediaPendingMembershipRecord.self, SharedMediaAcquisitionReceiptRecord.self, SharedMediaReceivingIntentRecord.self]
    }
}
