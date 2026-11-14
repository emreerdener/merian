import Foundation
import SwiftData

/// One bounded receiving slot per package. Scalars are lookup aids, never
/// admission, file, execution or cleanup authority. Typed owners must validate
/// canonical bytes and all reverse identities before interpreting any phase.
@Model
final class SharedMediaReceivingIntentRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) private(set) var cursorKey: String
    var schemaVersion: Int
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var ownerID: UUID
    var draftGeneration: UUID
    var operationID: UUID
    var phaseRaw: String
    var revision: Int64
    var preparedData: Data?
    var preparedSHA256: String
    var resultData: Data?
    var resultSHA256: String?
    /// Reserved for a separately qualified durable release-start owner.
    /// Any present or partial sidecar remains closed in this storage foundation.
    var releaseStartData: Data?
    var releaseStartSHA256: String?
    /// Durable allocation state belongs to the receiving owner; dormant until qualified.
    var allocationData: Data?
    var allocationSHA256: String?
    /// V69 original server facts; nil migration defaults confer no authority.
    /// Existing owners reject any populated or partial pair until integration.
    var initialAdmissionData: Data?
    var initialAdmissionSHA256: String?
    var initialCompletionData: Data?
    var initialCompletionSHA256: String?

    init(packageID: UUID, inventoryID: UUID, inventoryGeneration: UUID,
         ownerID: UUID, draftGeneration: UUID, operationID: UUID,
         preparedData: Data, preparedSHA256: String) {
        id = packageID
        cursorKey = packageID.uuidString.lowercased()
        schemaVersion = 1
        self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration
        self.ownerID = ownerID
        self.draftGeneration = draftGeneration
        self.operationID = operationID
        phaseRaw = "prepared"
        revision = 0
        self.preparedData = preparedData
        self.preparedSHA256 = preparedSHA256
        resultData = nil
        resultSHA256 = nil
        releaseStartData = nil
        releaseStartSHA256 = nil
        allocationData = nil
        allocationSHA256 = nil
        initialAdmissionData = nil
        initialAdmissionSHA256 = nil
        initialCompletionData = nil
        initialCompletionSHA256 = nil
    }
}
