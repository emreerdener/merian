import Foundation
import SwiftData

/// Frozen V72. Existing relationship graphs retain their immutable V71 types.
enum MerianSchemaV72: VersionedSchema {
    static var versionIdentifier = Schema.Version(72, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV72.LocalScanRecord.self, MerianSchemaV72.LocalAnalysisRecord.self, MerianSchemaV72.LocalAnalysisStateRecord.self,
         MerianSchemaV72.OfflineQueuedScan.self, MerianSchemaV72.CapturedMediaEntry.self, MerianSchemaV72.ScanCollection.self,
         MerianSchemaV72.PendingCloudDeletionTask.self, MerianSchemaV72.UserSpeciesPreference.self, MerianSchemaV72.OfflineJobRecord.self,
         MerianSchemaV72.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV72.PhotoPreparationRecord.self, MerianSchemaV72.PhotoPreparationAsset.self,
         MerianSchemaV72.PhotoPreparationReference.self, MerianSchemaV72.PhotoPreparationLease.self,
         MerianSchemaV72.SharedMediaInventoryRecord.self, MerianSchemaV72.SharedMediaAllocationRecord.self, MerianSchemaV72.SharedMediaReferenceRecord.self, MerianSchemaV72.SharedMediaLeaseRecord.self,
         MerianSchemaV72.SharedMediaInboxSourceRecord.self, MerianSchemaV72.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV72.SharedMediaDerivativePairRecord.self, MerianSchemaV72.SharedMediaDerivativeWorkRecord.self, MerianSchemaV72.SharedMediaConsumerRecord.self,
         MerianSchemaV72.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV72.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV72.SharedMediaPendingMembershipRecord.self, MerianSchemaV72.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV72.SharedMediaReceivingIntentRecord.self, MerianSchemaV72.SharedMediaOrdinaryTransferRecord.self, MerianSchemaV72.SharedMediaOrdinarySubmissionRecord.self, MerianSchemaV72.SharedMediaOrdinaryArtifactRecord.self]
    }
    typealias LocalScanRecord = MerianSchemaV71.LocalScanRecord
    typealias LocalAnalysisRecord = MerianSchemaV71.LocalAnalysisRecord
    typealias LocalAnalysisStateRecord = MerianSchemaV71.LocalAnalysisStateRecord
    typealias OfflineQueuedScan = MerianSchemaV71.OfflineQueuedScan
    typealias CapturedMediaEntry = MerianSchemaV71.CapturedMediaEntry
    typealias ScanCollection = MerianSchemaV71.ScanCollection
    typealias PendingCloudDeletionTask = MerianSchemaV71.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV71.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV71.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV71.OfflineQueueEvent
    typealias PhotoPreparationRecord = MerianSchemaV71.PhotoPreparationRecord
    typealias PhotoPreparationAsset = MerianSchemaV71.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV71.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV71.PhotoPreparationLease
    typealias SharedMediaInventoryRecord = MerianSchemaV71.SharedMediaInventoryRecord
    typealias SharedMediaAllocationRecord = MerianSchemaV71.SharedMediaAllocationRecord
    typealias SharedMediaReferenceRecord = MerianSchemaV71.SharedMediaReferenceRecord
    typealias SharedMediaLeaseRecord = MerianSchemaV71.SharedMediaLeaseRecord
    typealias SharedMediaInboxSourceRecord = MerianSchemaV71.SharedMediaInboxSourceRecord
    typealias SharedMediaInboxHandoffRecord = MerianSchemaV71.SharedMediaInboxHandoffRecord
    typealias SharedMediaDerivativePairRecord = MerianSchemaV71.SharedMediaDerivativePairRecord
    typealias SharedMediaDerivativeWorkRecord = MerianSchemaV71.SharedMediaDerivativeWorkRecord
    typealias SharedMediaConsumerRecord = MerianSchemaV71.SharedMediaConsumerRecord
    typealias SharedMediaAssetReferenceCountRecord = MerianSchemaV71.SharedMediaAssetReferenceCountRecord
    typealias SharedMediaMembershipBootstrapRecord = MerianSchemaV71.SharedMediaMembershipBootstrapRecord
    typealias SharedMediaPendingMembershipRecord = MerianSchemaV71.SharedMediaPendingMembershipRecord
    typealias SharedMediaAcquisitionReceiptRecord = MerianSchemaV71.SharedMediaAcquisitionReceiptRecord
    typealias SharedMediaReceivingIntentRecord = MerianSchemaV71.SharedMediaReceivingIntentRecord
    typealias SharedMediaOrdinaryTransferRecord = MerianSchemaV71.SharedMediaOrdinaryTransferRecord
    typealias SharedMediaOrdinarySubmissionRecord = MerianSchemaV71.SharedMediaOrdinarySubmissionRecord
}
