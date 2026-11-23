import Foundation
import SwiftData

/// Same-store cleanup carrier. These rows are never authority for normal media
/// access. Immutable header/page bodies are validated against the erasure cursor
/// before replay; generic purge must preserve them until cleanup acknowledges.
@Model
final class SharedMediaNativeErasurePageRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) private(set) var cursorKey: String
    var schemaVersion: Int
    var operationID: UUID
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var ownerID: UUID
    var profileSHA256: String
    var kindRaw: String
    var ordinal: Int64
    var bodyData: Data
    var bodySHA256: String

    init(id: UUID = UUID(), operationID: UUID, inventoryID: UUID,
         inventoryGeneration: UUID, ownerID: UUID, profileSHA256: String,
         kindRaw: String, ordinal: Int64, bodyData: Data, bodySHA256: String) {
        self.id = id; schemaVersion = 1
        self.operationID = operationID; self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration; self.ownerID = ownerID
        self.profileSHA256 = profileSHA256; self.kindRaw = kindRaw; self.ordinal = ordinal
        cursorKey = "\(operationID.uuidString.lowercased()):\(kindRaw):\(ordinal)"
        self.bodyData = bodyData; self.bodySHA256 = bodySHA256
    }
}
