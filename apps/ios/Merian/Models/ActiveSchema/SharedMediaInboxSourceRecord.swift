import Foundation
import SwiftData

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
