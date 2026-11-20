import Foundation
import SwiftData

/// Frozen outgoing V67; preserves allocation sidecars and the closed V64 relationship graph.
enum MerianSchemaV67: VersionedSchema {
    static var versionIdentifier = Schema.Version(67, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV67.LocalScanRecord.self, MerianSchemaV67.LocalAnalysisRecord.self, MerianSchemaV67.LocalAnalysisStateRecord.self,
         MerianSchemaV67.OfflineQueuedScan.self, MerianSchemaV67.CapturedMediaEntry.self, MerianSchemaV67.ScanCollection.self,
         MerianSchemaV67.PendingCloudDeletionTask.self, MerianSchemaV67.UserSpeciesPreference.self, MerianSchemaV67.OfflineJobRecord.self,
         MerianSchemaV67.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV67.PhotoPreparationRecord.self, MerianSchemaV67.PhotoPreparationAsset.self,
         MerianSchemaV67.PhotoPreparationReference.self, MerianSchemaV67.PhotoPreparationLease.self,
         MerianSchemaV67.SharedMediaInventoryRecord.self, MerianSchemaV67.SharedMediaAllocationRecord.self, MerianSchemaV67.SharedMediaReferenceRecord.self, MerianSchemaV67.SharedMediaLeaseRecord.self,
         MerianSchemaV67.SharedMediaInboxSourceRecord.self, MerianSchemaV67.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV67.SharedMediaDerivativePairRecord.self, MerianSchemaV67.SharedMediaDerivativeWorkRecord.self, MerianSchemaV67.SharedMediaConsumerRecord.self,
         MerianSchemaV67.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV67.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV67.SharedMediaPendingMembershipRecord.self, MerianSchemaV67.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV67.SharedMediaReceivingIntentRecord.self]
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
        /// Reserved for a separately qualified durable release-start owner.
        /// Any present or partial sidecar remains closed in this storage foundation.
        var releaseStartData: Data?
        var releaseStartSHA256: String?
        /// Durable allocation state belongs to the receiving owner; dormant until qualified.
        var allocationData: Data?
        var allocationSHA256: String?

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
            allocationData = nil
            allocationSHA256 = nil
        }
    }
}
