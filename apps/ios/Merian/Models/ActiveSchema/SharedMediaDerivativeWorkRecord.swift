import Foundation
import SwiftData

/// One role in a derivative pair; saved identity, not a pathname, governs recovery and release.
@Model
final class SharedMediaDerivativeWorkRecord {
    @Attribute(.unique) var id: UUID
    var pairID: UUID
    var roleRaw: String
    var assetID: UUID
    var assetGeneration: UUID
    var referenceID: UUID
    var leaseID: UUID
    var writerEpoch: UUID
    var byteCount: Int64
    var sha256: String
    var contentType: String
    var phaseRaw: String
    var writerStateRaw: String
    var partialDevice: Int64?
    var partialInode: Int64?
    var finalIdentity: String?
    var retirementID: UUID?
    var retirementPartialIdentity: String?
    var retirementFinalIdentity: String?
    var retirementParentIdentity: String?
    var retirementNamespaceIdentity: String?

    init(
        id: UUID,
        pairID: UUID,
        roleRaw: String,
        assetID: UUID,
        assetGeneration: UUID,
        referenceID: UUID,
        leaseID: UUID,
        writerEpoch: UUID,
        byteCount: Int64,
        sha256: String,
        contentType: String
    ) {
        self.id = id
        self.pairID = pairID
        self.roleRaw = roleRaw
        self.assetID = assetID
        self.assetGeneration = assetGeneration
        self.referenceID = referenceID
        self.leaseID = leaseID
        self.writerEpoch = writerEpoch
        self.byteCount = byteCount
        self.sha256 = sha256
        self.contentType = contentType
        phaseRaw = "planned"
        writerStateRaw = "absent"
    }
}
