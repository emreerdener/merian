import Foundation
import SwiftData

/// Frozen outgoing V70; preserves original admission/completion storage without inferring authority.
enum MerianSchemaV70: VersionedSchema {
    static var versionIdentifier = Schema.Version(70, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV70.LocalScanRecord.self, MerianSchemaV70.LocalAnalysisRecord.self, MerianSchemaV70.LocalAnalysisStateRecord.self,
         MerianSchemaV70.OfflineQueuedScan.self, MerianSchemaV70.CapturedMediaEntry.self, MerianSchemaV70.ScanCollection.self,
         MerianSchemaV70.PendingCloudDeletionTask.self, MerianSchemaV70.UserSpeciesPreference.self, MerianSchemaV70.OfflineJobRecord.self,
         MerianSchemaV70.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV70.PhotoPreparationRecord.self, MerianSchemaV70.PhotoPreparationAsset.self,
         MerianSchemaV70.PhotoPreparationReference.self, MerianSchemaV70.PhotoPreparationLease.self,
         MerianSchemaV70.SharedMediaInventoryRecord.self, MerianSchemaV70.SharedMediaAllocationRecord.self, MerianSchemaV70.SharedMediaReferenceRecord.self, MerianSchemaV70.SharedMediaLeaseRecord.self,
         MerianSchemaV70.SharedMediaInboxSourceRecord.self, MerianSchemaV70.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV70.SharedMediaDerivativePairRecord.self, MerianSchemaV70.SharedMediaDerivativeWorkRecord.self, MerianSchemaV70.SharedMediaConsumerRecord.self,
         MerianSchemaV70.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV70.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV70.SharedMediaPendingMembershipRecord.self, MerianSchemaV70.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV70.SharedMediaReceivingIntentRecord.self, MerianSchemaV70.SharedMediaOrdinaryTransferRecord.self]
    }
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
