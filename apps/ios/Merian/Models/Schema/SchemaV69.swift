import Foundation
import SwiftData

/// Frozen outgoing V69; preserves original admission/completion storage without inferring authority.
enum MerianSchemaV69: VersionedSchema {
    static var versionIdentifier = Schema.Version(69, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV69.LocalScanRecord.self, MerianSchemaV69.LocalAnalysisRecord.self, MerianSchemaV69.LocalAnalysisStateRecord.self,
         MerianSchemaV69.OfflineQueuedScan.self, MerianSchemaV69.CapturedMediaEntry.self, MerianSchemaV69.ScanCollection.self,
         MerianSchemaV69.PendingCloudDeletionTask.self, MerianSchemaV69.UserSpeciesPreference.self, MerianSchemaV69.OfflineJobRecord.self,
         MerianSchemaV69.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV69.PhotoPreparationRecord.self, MerianSchemaV69.PhotoPreparationAsset.self,
         MerianSchemaV69.PhotoPreparationReference.self, MerianSchemaV69.PhotoPreparationLease.self,
         MerianSchemaV69.SharedMediaInventoryRecord.self, MerianSchemaV69.SharedMediaAllocationRecord.self, MerianSchemaV69.SharedMediaReferenceRecord.self, MerianSchemaV69.SharedMediaLeaseRecord.self,
         MerianSchemaV69.SharedMediaInboxSourceRecord.self, MerianSchemaV69.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV69.SharedMediaDerivativePairRecord.self, MerianSchemaV69.SharedMediaDerivativeWorkRecord.self, MerianSchemaV69.SharedMediaConsumerRecord.self,
         MerianSchemaV69.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV69.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV69.SharedMediaPendingMembershipRecord.self, MerianSchemaV69.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV69.SharedMediaReceivingIntentRecord.self]
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
}
