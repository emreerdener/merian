import Foundation
import SwiftData

/// Immutable scalar inbox shape before adding derivative-pair ownership.
extension MerianSchemaV61 {

    /// Device-local, accountless source authority. The catalog is a projection of
    /// ready rows; neither legacy filenames nor the current login create ownership.
    @Model
    final class SharedMediaInboxSourceRecord {
        @Attribute(.unique) var id: UUID
        var inventoryID: UUID
        var generation: UUID
        var revision: Int64
        var receivedAt: Date
        var partialToken: String
        var finalToken: String
        var rootIdentity: String
        var maximumBytes: Int64
        var byteCount: Int64
        var sha256: String?
        var contentType: String?
        var partialDevice: Int64?
        var partialInode: Int64?
        var finalIdentity: String?
        var workID: UUID
        var writerEpoch: UUID
        var writerStateRaw: String
        var phaseRaw: String
        var retirementID: UUID?
        var retirementPartialIdentity: String?
        var retirementFinalIdentity: String?

        init(id: UUID, inventoryID: UUID, generation: UUID, receivedAt: Date,
             rootIdentity: String, maximumBytes: Int64, workID: UUID, writerEpoch: UUID) {
            self.id = id; self.inventoryID = inventoryID; self.generation = generation
            revision = 0; self.receivedAt = receivedAt
            finalToken = id.uuidString.lowercased(); partialToken = id.uuidString.lowercased() + ".partial"
            self.rootIdentity = rootIdentity; self.maximumBytes = maximumBytes; byteCount = 0
            self.workID = workID; self.writerEpoch = writerEpoch
            writerStateRaw = "open"; phaseRaw = "reserved"
        }
    }

    /// Exact retained local handoff. No operation here grants AI or remote authority.
    @Model
    final class SharedMediaInboxHandoffRecord {
        @Attribute(.unique) var id: UUID
        var nonce: UUID
        var sourceID: UUID
        var sourceGeneration: UUID
        var sourceRevision: Int64
        var inventoryGeneration: UUID
        var expectedInventoryRevision: Int64
        var ownerID: UUID
        var packageID: UUID
        var draftGeneration: UUID
        var assetID: UUID
        var assetGeneration: UUID
        var referenceID: UUID
        var leaseID: UUID
        var sourceHoldID: UUID
        var ordinal: Int64
        var byteCount: Int64
        var sha256: String
        var phaseRaw: String
        var writerEpoch: UUID
        var writerStateRaw: String
        var partialDevice: Int64?
        var partialInode: Int64?
        var finalIdentity: String?

        init(id: UUID, nonce: UUID, sourceID: UUID, sourceGeneration: UUID, sourceRevision: Int64,
             inventoryGeneration: UUID, expectedInventoryRevision: Int64, ownerID: UUID,
             packageID: UUID, draftGeneration: UUID, assetID: UUID, assetGeneration: UUID,
             referenceID: UUID, leaseID: UUID, sourceHoldID: UUID, ordinal: Int64,
             byteCount: Int64, sha256: String, writerEpoch: UUID) {
            self.id = id; self.nonce = nonce; self.sourceID = sourceID
            self.sourceGeneration = sourceGeneration; self.sourceRevision = sourceRevision
            self.inventoryGeneration = inventoryGeneration; self.expectedInventoryRevision = expectedInventoryRevision
            self.ownerID = ownerID; self.packageID = packageID; self.draftGeneration = draftGeneration
            self.assetID = assetID; self.assetGeneration = assetGeneration; self.referenceID = referenceID
            self.leaseID = leaseID; self.sourceHoldID = sourceHoldID; self.ordinal = ordinal
            self.byteCount = byteCount; self.sha256 = sha256; self.writerEpoch = writerEpoch
            phaseRaw = "reserved"; writerStateRaw = "open"
        }
    }
}
