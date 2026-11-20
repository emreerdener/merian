import Foundation
import SwiftData

/// Immutable scalar shared-storage shape before adding typed inbox ownership.
extension MerianSchemaV60 {

    @Model
    final class SharedMediaInventoryRecord {
        @Attribute(.unique) var id: UUID
        var rootIdentity: String
        var storeIdentity: String
        var generation: UUID
        var revision: Int64
        var modeRaw: String
        var phaseRaw: String
        var cursor: String

        init(id: UUID, rootIdentity: String, storeIdentity: String, generation: UUID, revision: Int64, modeRaw: String, phaseRaw: String, cursor: String) {
            self.id = id
            self.rootIdentity = rootIdentity
            self.storeIdentity = storeIdentity
            self.generation = generation
            self.revision = revision
            self.modeRaw = modeRaw
            self.phaseRaw = phaseRaw
            self.cursor = cursor
        }
    }

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

    @Model
    final class SharedMediaLeaseRecord {
        @Attribute(.unique) var id: UUID
        var allocationID: UUID
        var processEpoch: UUID
        var purposeRaw: String
        var stateRaw: String

        init(id: UUID, allocationID: UUID, processEpoch: UUID, purposeRaw: String, stateRaw: String) {
            self.id = id
            self.allocationID = allocationID
            self.processEpoch = processEpoch
            self.purposeRaw = purposeRaw
            self.stateRaw = stateRaw
        }
    }
}
