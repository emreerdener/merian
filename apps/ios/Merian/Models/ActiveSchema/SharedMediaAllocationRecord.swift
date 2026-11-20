import Foundation
import SwiftData

/// Inactive SMA-1 ownership. No file or server authority follows from a row.
@Model
final class SharedMediaAllocationRecord {
    @Attribute(.unique) var id: UUID
    var inventoryID: UUID
    var accountID: UUID?
    var packageID: UUID?
    var namespaceRaw: String
    var fileToken: String
    var poolRaw: String
    var stateRaw: String
    var materializedBytes: Int64
    var reservedBytes: Int64
    var physicalIdentity: String?

    init(id: UUID, inventoryID: UUID, accountID: UUID?, packageID: UUID?, namespaceRaw: String, fileToken: String, poolRaw: String, stateRaw: String, materializedBytes: Int64, reservedBytes: Int64, physicalIdentity: String?) {
        self.id = id
        self.inventoryID = inventoryID
        self.accountID = accountID
        self.packageID = packageID
        self.namespaceRaw = namespaceRaw
        self.fileToken = fileToken
        self.poolRaw = poolRaw
        self.stateRaw = stateRaw
        self.materializedBytes = materializedBytes
        self.reservedBytes = reservedBytes
        self.physicalIdentity = physicalIdentity
    }
}
