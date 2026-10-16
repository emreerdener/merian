import Foundation
import SwiftData

/// P1-L1 local ownership only. The fenced preparation repository owns all writes.
/// Scalar IDs are validated references, never implicit relationships or AI admission.
@Model
final class PhotoPreparationRecord {
    @Attribute(.unique) var id: UUID
    var ownerID: UUID
    var contractVersion: String
    var draftID: UUID
    var draftGeneration: UUID
    var revision: Int64
    var phaseRaw: String
    var supportingContextData: Data
    var allocatedByteCount: Int64
    var retirementRequested: Bool

    init(
        id: UUID,
        ownerID: UUID,
        contractVersion: String,
        draftID: UUID,
        draftGeneration: UUID,
        revision: Int64,
        phaseRaw: String,
        supportingContextData: Data,
        allocatedByteCount: Int64,
        retirementRequested: Bool
    ) {
        self.id = id
        self.ownerID = ownerID
        self.contractVersion = contractVersion
        self.draftID = draftID
        self.draftGeneration = draftGeneration
        self.revision = revision
        self.phaseRaw = phaseRaw
        self.supportingContextData = supportingContextData
        self.allocatedByteCount = allocatedByteCount
        self.retirementRequested = retirementRequested
    }
}
