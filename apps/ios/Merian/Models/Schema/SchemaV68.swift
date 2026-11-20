import Foundation
import SwiftData

/// Frozen outgoing V68; preserves queue presentation and exact receiving storage.
enum MerianSchemaV68: VersionedSchema {
    static var versionIdentifier = Schema.Version(68, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV68.LocalScanRecord.self, MerianSchemaV68.LocalAnalysisRecord.self, MerianSchemaV68.LocalAnalysisStateRecord.self,
         MerianSchemaV68.OfflineQueuedScan.self, MerianSchemaV68.CapturedMediaEntry.self, MerianSchemaV68.ScanCollection.self,
         MerianSchemaV68.PendingCloudDeletionTask.self, MerianSchemaV68.UserSpeciesPreference.self, MerianSchemaV68.OfflineJobRecord.self,
         MerianSchemaV68.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV68.PhotoPreparationRecord.self, MerianSchemaV68.PhotoPreparationAsset.self,
         MerianSchemaV68.PhotoPreparationReference.self, MerianSchemaV68.PhotoPreparationLease.self,
         MerianSchemaV68.SharedMediaInventoryRecord.self, MerianSchemaV68.SharedMediaAllocationRecord.self, MerianSchemaV68.SharedMediaReferenceRecord.self, MerianSchemaV68.SharedMediaLeaseRecord.self,
         MerianSchemaV68.SharedMediaInboxSourceRecord.self, MerianSchemaV68.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV68.SharedMediaDerivativePairRecord.self, MerianSchemaV68.SharedMediaDerivativeWorkRecord.self, MerianSchemaV68.SharedMediaConsumerRecord.self,
         MerianSchemaV68.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV68.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV68.SharedMediaPendingMembershipRecord.self, MerianSchemaV68.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV68.SharedMediaReceivingIntentRecord.self]
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

    typealias SharedMediaReceivingIntentRecord = MerianSchemaV67.SharedMediaReceivingIntentRecord
}
