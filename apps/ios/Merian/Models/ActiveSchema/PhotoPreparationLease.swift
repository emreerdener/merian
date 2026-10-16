import Foundation
import SwiftData

/// P1-L1 local ownership only. The fenced preparation repository owns all writes.
/// Scalar IDs are validated references, never implicit relationships or AI admission.
@Model
final class PhotoPreparationLease {
    @Attribute(.unique) var id: UUID
    var packageID: UUID
    var assetID: UUID
    var ownerID: UUID
    var processEpoch: UUID
    var purposeRaw: String
    var partialFileToken: String
    var finalFileToken: String
    var reservedByteCount: Int64
    var allocatedByteCount: Int64
    var writerStateRaw: String
    var sourceIdentity: String?
    var terminalProof: String?

    init(
        id: UUID,
        packageID: UUID,
        assetID: UUID,
        ownerID: UUID,
        processEpoch: UUID,
        purposeRaw: String,
        partialFileToken: String,
        finalFileToken: String,
        reservedByteCount: Int64,
        allocatedByteCount: Int64,
        writerStateRaw: String,
        terminalProof: String?,
        sourceIdentity: String? = nil
    ) {
        self.id = id
        self.packageID = packageID
        self.assetID = assetID
        self.ownerID = ownerID
        self.processEpoch = processEpoch
        self.purposeRaw = purposeRaw
        self.partialFileToken = partialFileToken
        self.finalFileToken = finalFileToken
        self.reservedByteCount = reservedByteCount
        self.allocatedByteCount = allocatedByteCount
        self.writerStateRaw = writerStateRaw
        self.terminalProof = terminalProof
        self.sourceIdentity = sourceIdentity
    }
}
