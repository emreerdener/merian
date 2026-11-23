import Foundation
import SwiftData

/// Durable review composition under the registered capture owner. No queue
/// cascade or UI lifecycle may erase this record while original holds remain.
/// Scalars are lookup aids; the exact bounded body and current owner are required.
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
