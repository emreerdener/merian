import Foundation
import SwiftData

/// Local file liability for one role of an immutable capture plan. Server-created
/// prepared audio has no row here. Queue deletion never cascades to this record.
/// The registered owner must validate request bytes, allocation and live leases;
/// these lookup fields alone grant no read, upload or deletion authority.
@Model
final class SharedMediaOrdinaryArtifactRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) private(set) var cursorKey: String
    @Attribute(.unique) private(set) var membershipKey: String
    var schemaVersion: Int
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var ownerID: UUID
    var recipientScanID: UUID
    var submissionGeneration: UUID
    var mediaID: UUID
    var itemIndex: Int
    var roleRaw: String
    var frameIndex: Int?
    var allocationID: UUID
    var referenceID: UUID
    var leaseID: UUID
    var writerEpoch: UUID
    var phaseRaw: String
    var revision: Int64
    var requestData: Data
    var requestSHA256: String
    var stageReceiptData: Data?
    var stageReceiptSHA256: String?
    var acceptanceData: Data?
    var acceptanceSHA256: String?
    var retirementData: Data?
    var retirementSHA256: String?

    init(id: UUID, inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID,
         recipientScanID: UUID, submissionGeneration: UUID, mediaID: UUID,
         itemIndex: Int, roleRaw: String, frameIndex: Int?, allocationID: UUID,
         referenceID: UUID, leaseID: UUID, writerEpoch: UUID,
         requestData: Data, requestSHA256: String) {
        self.id = id; cursorKey = id.uuidString.lowercased()
        membershipKey = [ownerID, recipientScanID, submissionGeneration, mediaID]
            .map { $0.uuidString.lowercased() }.joined(separator: ":")
        schemaVersion = 1
        self.inventoryID = inventoryID; self.inventoryGeneration = inventoryGeneration; self.ownerID = ownerID
        self.recipientScanID = recipientScanID; self.submissionGeneration = submissionGeneration; self.mediaID = mediaID
        self.itemIndex = itemIndex; self.roleRaw = roleRaw; self.frameIndex = frameIndex
        self.allocationID = allocationID; self.referenceID = referenceID; self.leaseID = leaseID; self.writerEpoch = writerEpoch
        phaseRaw = "reserved"; revision = 0; self.requestData = requestData; self.requestSHA256 = requestSHA256
        stageReceiptData = nil; stageReceiptSHA256 = nil; acceptanceData = nil; acceptanceSHA256 = nil
        retirementData = nil; retirementSHA256 = nil
    }
}
