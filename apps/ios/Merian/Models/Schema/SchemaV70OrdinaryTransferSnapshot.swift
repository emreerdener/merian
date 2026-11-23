import Foundation
import SwiftData

// Immutable V70 ordinary hold storage.
extension MerianSchemaV70 {
    /// Durable ordinary-queue hold on a registered owner's original. Lookup scalars never authorize file
    /// access or cleanup; the registered owner validates exact versioned envelopes.
    /// No row is inferred from an existing queue, receipt or source during migration.
    @Model
    final class SharedMediaOrdinaryTransferRecord {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) private(set) var cursorKey: String
        var schemaVersion: Int
        var inventoryID: UUID
        var inventoryGeneration: UUID
        var ownerID: UUID
        var sourceAssetID: UUID
        var sourceReferenceID: UUID
        var recipientScanID: UUID
        var submissionGeneration: UUID
        var writerEpoch: UUID
        var phaseRaw: String
        var revision: Int64
        /// Exact source generation/revision, immutable byte identity,
        /// recipient request identity and maximum byte liability precede all I/O.
        var requestData: Data
        var requestSHA256: String
        /// A verified remote upload is not yet queue acceptance or eviction authority.
        var completionData: Data?
        var completionSHA256: String?
        /// Survives ordinary job cleanup so a lost acknowledgement remains exact.
        var acceptanceData: Data?
        var acceptanceSHA256: String?
        /// Hold release intent and active-reader/upload termination evidence.
        /// Releasing this row never authorizes unlinking the owner-managed original.
        var retirementData: Data?
        var retirementSHA256: String?

        init(id: UUID, inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID,
             sourceAssetID: UUID, sourceReferenceID: UUID, recipientScanID: UUID,
             submissionGeneration: UUID, writerEpoch: UUID, requestData: Data,
             requestSHA256: String) {
            self.id = id
            cursorKey = id.uuidString.lowercased()
            schemaVersion = 1
            self.inventoryID = inventoryID
            self.inventoryGeneration = inventoryGeneration
            self.ownerID = ownerID
            self.sourceAssetID = sourceAssetID
            self.sourceReferenceID = sourceReferenceID
            self.recipientScanID = recipientScanID
            self.submissionGeneration = submissionGeneration
            self.writerEpoch = writerEpoch
            phaseRaw = "reserved"
            revision = 0
            self.requestData = requestData
            self.requestSHA256 = requestSHA256
            completionData = nil
            completionSHA256 = nil
            acceptanceData = nil
            acceptanceSHA256 = nil
            retirementData = nil
            retirementSHA256 = nil
        }
    }
}
