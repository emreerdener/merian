import Foundation
import SwiftData

/// Inactive SMA-1 ownership. No file or server authority follows from a row.
@Model
final class SharedMediaReferenceRecord {
    @Attribute(.unique) var id: UUID
    var allocationID: UUID
    var accountID: UUID?
    var ownerID: String
    var roleRaw: String
    var stateRaw: String
    var revision: Int64

    init(id: UUID, allocationID: UUID, accountID: UUID?, ownerID: String, roleRaw: String, stateRaw: String, revision: Int64) {
        self.id = id
        self.allocationID = allocationID
        self.accountID = accountID
        self.ownerID = ownerID
        self.roleRaw = roleRaw
        self.stateRaw = stateRaw
        self.revision = revision
    }
}
