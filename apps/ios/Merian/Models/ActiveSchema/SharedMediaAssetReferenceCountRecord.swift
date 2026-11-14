import Foundation
import SwiftData

/// Same-transaction reverse accounting. A zero count alone never authorizes unlink.
@Model
final class SharedMediaAssetReferenceCountRecord {
    @Attribute(.unique) var id: UUID
    var assetGeneration: UUID
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var ownerID: UUID
    var liveCount: Int64
    var revision: Int64
    var retirementID: UUID?

    init(assetID: UUID, assetGeneration: UUID, inventoryID: UUID,
         inventoryGeneration: UUID, ownerID: UUID, liveCount: Int64) {
        id = assetID
        self.assetGeneration = assetGeneration
        self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration
        self.ownerID = ownerID
        self.liveCount = liveCount
        revision = 0
    }
}
