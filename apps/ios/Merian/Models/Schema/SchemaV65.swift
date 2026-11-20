import SwiftData

/// Frozen outgoing V65. Receiving bytes and the entire V64 relationship graph stay unchanged.
enum MerianSchemaV65: VersionedSchema {
    static var versionIdentifier = Schema.Version(65, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV65.LocalScanRecord.self, MerianSchemaV65.LocalAnalysisRecord.self, MerianSchemaV65.LocalAnalysisStateRecord.self,
         MerianSchemaV65.OfflineQueuedScan.self, MerianSchemaV65.CapturedMediaEntry.self, MerianSchemaV65.ScanCollection.self,
         MerianSchemaV65.PendingCloudDeletionTask.self, MerianSchemaV65.UserSpeciesPreference.self, MerianSchemaV65.OfflineJobRecord.self,
         MerianSchemaV65.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV65.PhotoPreparationRecord.self, MerianSchemaV65.PhotoPreparationAsset.self,
         MerianSchemaV65.PhotoPreparationReference.self, MerianSchemaV65.PhotoPreparationLease.self,
         MerianSchemaV65.SharedMediaInventoryRecord.self, MerianSchemaV65.SharedMediaAllocationRecord.self, MerianSchemaV65.SharedMediaReferenceRecord.self, MerianSchemaV65.SharedMediaLeaseRecord.self,
         MerianSchemaV65.SharedMediaInboxSourceRecord.self, MerianSchemaV65.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV65.SharedMediaDerivativePairRecord.self, MerianSchemaV65.SharedMediaDerivativeWorkRecord.self, MerianSchemaV65.SharedMediaConsumerRecord.self,
         MerianSchemaV65.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV65.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV65.SharedMediaPendingMembershipRecord.self, MerianSchemaV65.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV65.SharedMediaReceivingIntentRecord.self]
    }
    typealias LocalScanRecord = MerianSchemaV64.LocalScanRecord
    typealias LocalAnalysisRecord = MerianSchemaV64.LocalAnalysisRecord
    typealias LocalAnalysisStateRecord = MerianSchemaV64.LocalAnalysisStateRecord
    typealias OfflineQueuedScan = MerianSchemaV64.OfflineQueuedScan
    typealias CapturedMediaEntry = MerianSchemaV64.CapturedMediaEntry
    typealias ScanCollection = MerianSchemaV64.ScanCollection
    typealias PendingCloudDeletionTask = MerianSchemaV64.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV64.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV64.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV64.OfflineQueueEvent
    typealias PhotoPreparationRecord = MerianSchemaV64.PhotoPreparationRecord
    typealias PhotoPreparationAsset = MerianSchemaV64.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV64.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV64.PhotoPreparationLease
    typealias SharedMediaInventoryRecord = MerianSchemaV64.SharedMediaInventoryRecord
    typealias SharedMediaAllocationRecord = MerianSchemaV64.SharedMediaAllocationRecord
    typealias SharedMediaReferenceRecord = MerianSchemaV64.SharedMediaReferenceRecord
    typealias SharedMediaLeaseRecord = MerianSchemaV64.SharedMediaLeaseRecord
    typealias SharedMediaInboxSourceRecord = MerianSchemaV64.SharedMediaInboxSourceRecord
    typealias SharedMediaInboxHandoffRecord = MerianSchemaV64.SharedMediaInboxHandoffRecord
    typealias SharedMediaDerivativePairRecord = MerianSchemaV64.SharedMediaDerivativePairRecord
    typealias SharedMediaDerivativeWorkRecord = MerianSchemaV64.SharedMediaDerivativeWorkRecord
    typealias SharedMediaConsumerRecord = MerianSchemaV64.SharedMediaConsumerRecord
    typealias SharedMediaAssetReferenceCountRecord = MerianSchemaV64.SharedMediaAssetReferenceCountRecord
    typealias SharedMediaMembershipBootstrapRecord = MerianSchemaV64.SharedMediaMembershipBootstrapRecord
    typealias SharedMediaPendingMembershipRecord = MerianSchemaV64.SharedMediaPendingMembershipRecord
    typealias SharedMediaAcquisitionReceiptRecord = MerianSchemaV64.SharedMediaAcquisitionReceiptRecord
}
