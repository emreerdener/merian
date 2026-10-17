import Foundation
import SwiftData

/// Bounded pending lookup aid. Exact joined rows remain the ownership authority.
@Model
final class SharedMediaPendingMembershipRecord {
    @Attribute(.unique) var id: UUID
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var ownerID: UUID
    var draftGeneration: UUID
    var revision: Int64
    var membersData: Data

    init(packageID: UUID, inventoryID: UUID, inventoryGeneration: UUID,
         ownerID: UUID, draftGeneration: UUID, membersData: Data) {
        id = packageID
        self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration
        self.ownerID = ownerID
        self.draftGeneration = draftGeneration
        self.membersData = membersData
        revision = 0
    }
}
