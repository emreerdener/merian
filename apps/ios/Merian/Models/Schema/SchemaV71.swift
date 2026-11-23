import Foundation
import SwiftData

/// Frozen outgoing V71; preserves original admission/completion storage without inferring authority.
enum MerianSchemaV71: VersionedSchema {
    static var versionIdentifier = Schema.Version(71, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV71.LocalScanRecord.self, MerianSchemaV71.LocalAnalysisRecord.self, MerianSchemaV71.LocalAnalysisStateRecord.self,
         MerianSchemaV71.OfflineQueuedScan.self, MerianSchemaV71.CapturedMediaEntry.self, MerianSchemaV71.ScanCollection.self,
         MerianSchemaV71.PendingCloudDeletionTask.self, MerianSchemaV71.UserSpeciesPreference.self, MerianSchemaV71.OfflineJobRecord.self,
         MerianSchemaV71.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV71.PhotoPreparationRecord.self, MerianSchemaV71.PhotoPreparationAsset.self,
         MerianSchemaV71.PhotoPreparationReference.self, MerianSchemaV71.PhotoPreparationLease.self,
         MerianSchemaV71.SharedMediaInventoryRecord.self, MerianSchemaV71.SharedMediaAllocationRecord.self, MerianSchemaV71.SharedMediaReferenceRecord.self, MerianSchemaV71.SharedMediaLeaseRecord.self,
         MerianSchemaV71.SharedMediaInboxSourceRecord.self, MerianSchemaV71.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV71.SharedMediaDerivativePairRecord.self, MerianSchemaV71.SharedMediaDerivativeWorkRecord.self, MerianSchemaV71.SharedMediaConsumerRecord.self,
         MerianSchemaV71.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV71.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV71.SharedMediaPendingMembershipRecord.self, MerianSchemaV71.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV71.SharedMediaReceivingIntentRecord.self, MerianSchemaV71.SharedMediaOrdinaryTransferRecord.self, MerianSchemaV71.SharedMediaOrdinarySubmissionRecord.self]
    }
    typealias SharedMediaOrdinaryTransferRecord = MerianSchemaV70.SharedMediaOrdinaryTransferRecord
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
    typealias SharedMediaReceivingIntentRecord = MerianSchemaV69.SharedMediaReceivingIntentRecord
}
