import Foundation
import SwiftData

/// Scalar native ownership. Only a joined, fenced transaction may create or transfer it.
/// A digest asserts the immutable ledger cohort; it never grants file or AI authority.
@Model
final class SharedMediaConsumerRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) private(set) var cursorKey: String
    var kindRaw: String
    var consumerID: String
    var originQueueID: String
    var observationID: String
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var ownerID: UUID
    @Attribute(.unique) var packageID: UUID
    var draftGeneration: UUID
    var frozenPackageRevision: Int64
    var contractVersion: String
    var digestVersion: Int
    var cohortData: Data = Data()
    var cohortSHA256: String
    var executionKindRaw: String
    var inferenceGeneration: UUID?
    var retirementID: UUID?
    var lifecycleRaw: String
    var revision: Int64

    init(id: UUID, kindRaw: String, consumerID: String, originQueueID: String,
         observationID: String, inventoryID: UUID, inventoryGeneration: UUID,
         ownerID: UUID, packageID: UUID, draftGeneration: UUID,
         frozenPackageRevision: Int64, contractVersion: String, digestVersion: Int,
         cohortSHA256: String, executionKindRaw: String, inferenceGeneration: UUID?) {
        self.id = id
        cursorKey = id.uuidString.lowercased()
        self.kindRaw = kindRaw
        self.consumerID = consumerID
        self.originQueueID = originQueueID
        self.observationID = observationID
        self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration
        self.ownerID = ownerID
        self.packageID = packageID
        self.draftGeneration = draftGeneration
        self.frozenPackageRevision = frozenPackageRevision
        self.contractVersion = contractVersion
        self.digestVersion = digestVersion
        self.cohortSHA256 = cohortSHA256
        self.executionKindRaw = executionKindRaw
        self.inferenceGeneration = inferenceGeneration
        lifecycleRaw = "active"
        revision = 0
    }
}
