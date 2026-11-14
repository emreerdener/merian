import Foundation
import SwiftData

/// Frozen outgoing V66; release sidecars and the closed V64 graph stay unchanged.
enum MerianSchemaV66: VersionedSchema {
    static var versionIdentifier = Schema.Version(66, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV66.LocalScanRecord.self, MerianSchemaV66.LocalAnalysisRecord.self, MerianSchemaV66.LocalAnalysisStateRecord.self,
         MerianSchemaV66.OfflineQueuedScan.self, MerianSchemaV66.CapturedMediaEntry.self, MerianSchemaV66.ScanCollection.self,
         MerianSchemaV66.PendingCloudDeletionTask.self, MerianSchemaV66.UserSpeciesPreference.self, MerianSchemaV66.OfflineJobRecord.self,
         MerianSchemaV66.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV66.PhotoPreparationRecord.self, MerianSchemaV66.PhotoPreparationAsset.self,
         MerianSchemaV66.PhotoPreparationReference.self, MerianSchemaV66.PhotoPreparationLease.self,
         MerianSchemaV66.SharedMediaInventoryRecord.self, MerianSchemaV66.SharedMediaAllocationRecord.self, MerianSchemaV66.SharedMediaReferenceRecord.self, MerianSchemaV66.SharedMediaLeaseRecord.self,
         MerianSchemaV66.SharedMediaInboxSourceRecord.self, MerianSchemaV66.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV66.SharedMediaDerivativePairRecord.self, MerianSchemaV66.SharedMediaDerivativeWorkRecord.self, MerianSchemaV66.SharedMediaConsumerRecord.self,
         MerianSchemaV66.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV66.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV66.SharedMediaPendingMembershipRecord.self, MerianSchemaV66.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV66.SharedMediaReceivingIntentRecord.self]
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

    @Model
    final class SharedMediaReceivingIntentRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) private(set) var cursorKey: String
        var schemaVersion: Int
        var inventoryID: UUID
        var inventoryGeneration: UUID
        var ownerID: UUID
        var draftGeneration: UUID
        var operationID: UUID
        var phaseRaw: String
        var revision: Int64
        var preparedData: Data?
        var preparedSHA256: String
        var resultData: Data?
        var resultSHA256: String?
        var releaseStartData: Data?
        var releaseStartSHA256: String?

        init(packageID: UUID, inventoryID: UUID, inventoryGeneration: UUID,
             ownerID: UUID, draftGeneration: UUID, operationID: UUID,
             preparedData: Data, preparedSHA256: String) {
            id = packageID
            cursorKey = packageID.uuidString.lowercased()
            schemaVersion = 1
            self.inventoryID = inventoryID
            self.inventoryGeneration = inventoryGeneration
            self.ownerID = ownerID
            self.draftGeneration = draftGeneration
            self.operationID = operationID
            phaseRaw = "prepared"
            revision = 0
            self.preparedData = preparedData
            self.preparedSHA256 = preparedSHA256
            resultData = nil
            resultSHA256 = nil
            releaseStartData = nil
            releaseStartSHA256 = nil
        }
    }
}
