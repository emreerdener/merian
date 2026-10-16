import Foundation
import SwiftData

/// Immutable P1 ownership shape before shared allocation.
extension MerianSchemaV59 {
    /// P1-L1 local ownership only. The fenced preparation repository owns all writes.
    /// Scalar IDs are validated references, never implicit relationships or AI admission.
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

    /// P1-L1 local ownership only. The fenced preparation repository owns all writes.
    /// Scalar IDs are validated references, never implicit relationships or AI admission.
    @Model
    final class PhotoPreparationAsset {
        @Attribute(.unique) var id: UUID
        var ownerID: UUID
        var generation: UUID
        var fileToken: String
        var contentType: String
        var byteCount: Int64
        var sha256: String
        var acquisitionKindRaw: String
        var cleanupStateRaw: String

        init(
            id: UUID,
            ownerID: UUID,
            generation: UUID,
            fileToken: String,
            contentType: String,
            byteCount: Int64,
            sha256: String,
            acquisitionKindRaw: String,
            cleanupStateRaw: String
        ) {
            self.id = id
            self.ownerID = ownerID
            self.generation = generation
            self.fileToken = fileToken
            self.contentType = contentType
            self.byteCount = byteCount
            self.sha256 = sha256
            self.acquisitionKindRaw = acquisitionKindRaw
            self.cleanupStateRaw = cleanupStateRaw
        }
    }

    /// P1-L1 local ownership only. The fenced preparation repository owns all writes.
    /// Scalar IDs are validated references, never implicit relationships or AI admission.
    @Model
    final class PhotoPreparationReference {
        @Attribute(.unique) var id: UUID
        var packageID: UUID
        var assetID: UUID
        var ownerID: UUID
        var roleRaw: String
        var ordinal: Int64
        var revision: Int64
        var isLive: Bool

        init(
            id: UUID,
            packageID: UUID,
            assetID: UUID,
            ownerID: UUID,
            roleRaw: String,
            ordinal: Int64,
            revision: Int64,
            isLive: Bool
        ) {
            self.id = id
            self.packageID = packageID
            self.assetID = assetID
            self.ownerID = ownerID
            self.roleRaw = roleRaw
            self.ordinal = ordinal
            self.revision = revision
            self.isLive = isLive
        }
    }

    /// P1-L1 local ownership only. The fenced preparation repository owns all writes.
    /// Scalar IDs are validated references, never implicit relationships or AI admission.
    @Model
    final class PhotoPreparationLease {
        @Attribute(.unique) var id: UUID
        var packageID: UUID
        var assetID: UUID
        var ownerID: UUID
        var processEpoch: UUID
        var purposeRaw: String
        var partialFileToken: String
        var finalFileToken: String
        var reservedByteCount: Int64
        var allocatedByteCount: Int64
        var writerStateRaw: String
        var sourceIdentity: String?
        var terminalProof: String?

        init(
            id: UUID,
            packageID: UUID,
            assetID: UUID,
            ownerID: UUID,
            processEpoch: UUID,
            purposeRaw: String,
            partialFileToken: String,
            finalFileToken: String,
            reservedByteCount: Int64,
            allocatedByteCount: Int64,
            writerStateRaw: String,
            terminalProof: String?,
            sourceIdentity: String? = nil
        ) {
            self.id = id
            self.packageID = packageID
            self.assetID = assetID
            self.ownerID = ownerID
            self.processEpoch = processEpoch
            self.purposeRaw = purposeRaw
            self.partialFileToken = partialFileToken
            self.finalFileToken = finalFileToken
            self.reservedByteCount = reservedByteCount
            self.allocatedByteCount = allocatedByteCount
            self.writerStateRaw = writerStateRaw
            self.terminalProof = terminalProof
            self.sourceIdentity = sourceIdentity
        }
    }
}
