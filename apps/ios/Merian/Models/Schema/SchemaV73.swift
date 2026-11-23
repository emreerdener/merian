import Foundation
import SwiftData

/// Frozen V73. Its review journal shape is preserved before adding erasure storage.
enum MerianSchemaV73: VersionedSchema {
    static var versionIdentifier = Schema.Version(73, 0, 0)
    static var models: [any PersistentModel.Type] {
        [MerianSchemaV73.LocalScanRecord.self, MerianSchemaV73.LocalAnalysisRecord.self, MerianSchemaV73.LocalAnalysisStateRecord.self,
         MerianSchemaV73.OfflineQueuedScan.self, MerianSchemaV73.CapturedMediaEntry.self, MerianSchemaV73.ScanCollection.self,
         MerianSchemaV73.PendingCloudDeletionTask.self, MerianSchemaV73.UserSpeciesPreference.self, MerianSchemaV73.OfflineJobRecord.self,
         MerianSchemaV73.OfflineQueueEvent.self, MerianActiveSchemaV50.OfflineQueuedScanGoalHint.self,
         MerianSchemaV73.PhotoPreparationRecord.self, MerianSchemaV73.PhotoPreparationAsset.self,
         MerianSchemaV73.PhotoPreparationReference.self, MerianSchemaV73.PhotoPreparationLease.self,
         MerianSchemaV73.SharedMediaInventoryRecord.self, MerianSchemaV73.SharedMediaAllocationRecord.self, MerianSchemaV73.SharedMediaReferenceRecord.self, MerianSchemaV73.SharedMediaLeaseRecord.self,
         MerianSchemaV73.SharedMediaInboxSourceRecord.self, MerianSchemaV73.SharedMediaInboxHandoffRecord.self,
         MerianSchemaV73.SharedMediaDerivativePairRecord.self, MerianSchemaV73.SharedMediaDerivativeWorkRecord.self, MerianSchemaV73.SharedMediaConsumerRecord.self,
         MerianSchemaV73.SharedMediaAssetReferenceCountRecord.self, MerianSchemaV73.SharedMediaMembershipBootstrapRecord.self, MerianSchemaV73.SharedMediaPendingMembershipRecord.self, MerianSchemaV73.SharedMediaAcquisitionReceiptRecord.self, MerianSchemaV73.SharedMediaReceivingIntentRecord.self, MerianSchemaV73.SharedMediaOrdinaryTransferRecord.self, MerianSchemaV73.SharedMediaOrdinarySubmissionRecord.self, MerianSchemaV73.SharedMediaOrdinaryArtifactRecord.self, MerianSchemaV73.SharedMediaCaptureDraftJournalRecord.self]
    }
    typealias LocalScanRecord = MerianSchemaV72.LocalScanRecord
    typealias LocalAnalysisRecord = MerianSchemaV72.LocalAnalysisRecord
    typealias LocalAnalysisStateRecord = MerianSchemaV72.LocalAnalysisStateRecord
    typealias OfflineQueuedScan = MerianSchemaV72.OfflineQueuedScan
    typealias CapturedMediaEntry = MerianSchemaV72.CapturedMediaEntry
    typealias ScanCollection = MerianSchemaV72.ScanCollection
    typealias PendingCloudDeletionTask = MerianSchemaV72.PendingCloudDeletionTask
    typealias UserSpeciesPreference = MerianSchemaV72.UserSpeciesPreference
    typealias OfflineJobRecord = MerianSchemaV72.OfflineJobRecord
    typealias OfflineQueueEvent = MerianSchemaV72.OfflineQueueEvent
    typealias PhotoPreparationRecord = MerianSchemaV72.PhotoPreparationRecord
    typealias PhotoPreparationAsset = MerianSchemaV72.PhotoPreparationAsset
    typealias PhotoPreparationReference = MerianSchemaV72.PhotoPreparationReference
    typealias PhotoPreparationLease = MerianSchemaV72.PhotoPreparationLease
    typealias SharedMediaInventoryRecord = MerianSchemaV72.SharedMediaInventoryRecord
    typealias SharedMediaAllocationRecord = MerianSchemaV72.SharedMediaAllocationRecord
    typealias SharedMediaReferenceRecord = MerianSchemaV72.SharedMediaReferenceRecord
    typealias SharedMediaLeaseRecord = MerianSchemaV72.SharedMediaLeaseRecord
    typealias SharedMediaInboxSourceRecord = MerianSchemaV72.SharedMediaInboxSourceRecord
    typealias SharedMediaInboxHandoffRecord = MerianSchemaV72.SharedMediaInboxHandoffRecord
    typealias SharedMediaDerivativePairRecord = MerianSchemaV72.SharedMediaDerivativePairRecord
    typealias SharedMediaDerivativeWorkRecord = MerianSchemaV72.SharedMediaDerivativeWorkRecord
    typealias SharedMediaConsumerRecord = MerianSchemaV72.SharedMediaConsumerRecord
    typealias SharedMediaAssetReferenceCountRecord = MerianSchemaV72.SharedMediaAssetReferenceCountRecord
    typealias SharedMediaMembershipBootstrapRecord = MerianSchemaV72.SharedMediaMembershipBootstrapRecord
    typealias SharedMediaPendingMembershipRecord = MerianSchemaV72.SharedMediaPendingMembershipRecord
    typealias SharedMediaAcquisitionReceiptRecord = MerianSchemaV72.SharedMediaAcquisitionReceiptRecord
    typealias SharedMediaReceivingIntentRecord = MerianSchemaV72.SharedMediaReceivingIntentRecord
    typealias SharedMediaOrdinaryTransferRecord = MerianSchemaV72.SharedMediaOrdinaryTransferRecord
    typealias SharedMediaOrdinarySubmissionRecord = MerianSchemaV72.SharedMediaOrdinarySubmissionRecord
    typealias SharedMediaOrdinaryArtifactRecord = MerianSchemaV72.SharedMediaOrdinaryArtifactRecord

    @Model
    final class SharedMediaCaptureDraftJournalRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) private(set) var cursorKey: String
        @Attribute(.unique) private(set) var scanKey: String
        var schemaVersion: Int
        var inventoryID: UUID
        var inventoryGeneration: UUID
        var ownerID: UUID
        var scanID: UUID
        var rootBindingSHA256: String
        var revision: Int64
        var bodyData: Data
        var bodySHA256: String

        init(generation: UUID, inventoryID: UUID, inventoryGeneration: UUID,
             ownerID: UUID, scanID: UUID, rootBindingSHA256: String,
             bodyData: Data, bodySHA256: String) {
            id = generation; cursorKey = generation.uuidString.lowercased()
            scanKey = [ownerID, scanID].map { $0.uuidString.lowercased() }.joined(separator: ":")
            schemaVersion = 1; revision = 0
            self.inventoryID = inventoryID; self.inventoryGeneration = inventoryGeneration
            self.ownerID = ownerID; self.scanID = scanID; self.rootBindingSHA256 = rootBindingSHA256
            self.bodyData = bodyData; self.bodySHA256 = bodySHA256
        }
    }
}
