import Foundation
import SwiftData

/// Immutable outgoing V62 shapes, captured before consumer ownership fields.
extension MerianSchemaV62 {

    @Model
    final class PhotoPreparationRecord {
        @Attribute(.unique) var id: UUID
        var ownerID: UUID
        var contractVersion: String
        var draftID: UUID
        var draftGeneration: UUID
        var revision: Int64
        var phaseRaw: String
        var supportingContextData: Data
        var allocatedByteCount: Int64
        var retirementRequested: Bool

        init(
            id: UUID,
            ownerID: UUID,
            contractVersion: String,
            draftID: UUID,
            draftGeneration: UUID,
            revision: Int64,
            phaseRaw: String,
            supportingContextData: Data,
            allocatedByteCount: Int64,
            retirementRequested: Bool
        ) {
            self.id = id
            self.ownerID = ownerID
            self.contractVersion = contractVersion
            self.draftID = draftID
            self.draftGeneration = draftGeneration
            self.revision = revision
            self.phaseRaw = phaseRaw
            self.supportingContextData = supportingContextData
            self.allocatedByteCount = allocatedByteCount
            self.retirementRequested = retirementRequested
        }
    }

    @Model
    final class SharedMediaDerivativePairRecord {
        @Attribute(.unique) var id: UUID
        var nonce: UUID
        var contractVersion: String
        var inventoryID: UUID
        var inventoryGeneration: UUID
        var expectedInventoryRevision: Int64
        var ownerID: UUID
        var packageID: UUID
        var draftGeneration: UUID
        var originalReferenceID: UUID
        var originalReferenceRevision: Int64
        var originalAssetID: UUID
        var originalAssetGeneration: UUID
        var ordinal: Int64
        var expectedPackageRevision: Int64
        var aiWorkID: UUID
        var displayWorkID: UUID
        var previousPairID: UUID?
        var phaseRaw: String
        var publishedRevision: Int64?

        init(
            id: UUID,
            nonce: UUID,
            inventoryID: UUID,
            inventoryGeneration: UUID,
            expectedInventoryRevision: Int64,
            ownerID: UUID,
            packageID: UUID,
            draftGeneration: UUID,
            originalReferenceID: UUID,
            originalReferenceRevision: Int64,
            originalAssetID: UUID,
            originalAssetGeneration: UUID,
            ordinal: Int64,
            expectedPackageRevision: Int64,
            aiWorkID: UUID,
            displayWorkID: UUID,
            previousPairID: UUID? = nil
        ) {
            self.id = id
            self.nonce = nonce
            self.inventoryID = inventoryID
            self.inventoryGeneration = inventoryGeneration
            self.expectedInventoryRevision = expectedInventoryRevision
            self.ownerID = ownerID
            self.packageID = packageID
            self.draftGeneration = draftGeneration
            self.originalReferenceID = originalReferenceID
            self.originalReferenceRevision = originalReferenceRevision
            self.originalAssetID = originalAssetID
            self.originalAssetGeneration = originalAssetGeneration
            self.ordinal = ordinal
            self.expectedPackageRevision = expectedPackageRevision
            self.aiWorkID = aiWorkID
            self.displayWorkID = displayWorkID
            self.previousPairID = previousPairID
            contractVersion = "sharedDerivativeV1"
            phaseRaw = "planned"
        }
    }

    @Model
    final class SharedMediaDerivativeWorkRecord {
        @Attribute(.unique) var id: UUID
        var pairID: UUID
        var roleRaw: String
        var assetID: UUID
        var assetGeneration: UUID
        var referenceID: UUID
        var leaseID: UUID
        var writerEpoch: UUID
        var byteCount: Int64
        var sha256: String
        var contentType: String
        var phaseRaw: String
        var writerStateRaw: String
        var partialDevice: Int64?
        var partialInode: Int64?
        var finalIdentity: String?
        var retirementID: UUID?
        var retirementPartialIdentity: String?
        var retirementFinalIdentity: String?
        var retirementParentIdentity: String?
        var retirementNamespaceIdentity: String?

        init(
            id: UUID,
            pairID: UUID,
            roleRaw: String,
            assetID: UUID,
            assetGeneration: UUID,
            referenceID: UUID,
            leaseID: UUID,
            writerEpoch: UUID,
            byteCount: Int64,
            sha256: String,
            contentType: String
        ) {
            self.id = id
            self.pairID = pairID
            self.roleRaw = roleRaw
            self.assetID = assetID
            self.assetGeneration = assetGeneration
            self.referenceID = referenceID
            self.leaseID = leaseID
            self.writerEpoch = writerEpoch
            self.byteCount = byteCount
            self.sha256 = sha256
            self.contentType = contentType
            phaseRaw = "planned"
            writerStateRaw = "absent"
        }
    }
}
