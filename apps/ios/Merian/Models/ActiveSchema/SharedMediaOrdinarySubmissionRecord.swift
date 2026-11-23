import Foundation
import SwiftData

/// One durable ordinary submission, independent of queue/job cleanup.
/// Scalars are lookup aids. Only a qualified owner may interpret the versioned
/// body, accept its complete hold set or erase its payload after dependencies end.
/// Migration never synthesizes this record from legacy queue or hold rows.
@Model
final class SharedMediaOrdinarySubmissionRecord {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) private(set) var cursorKey: String
    @Attribute(.unique) private(set) var identityKey: String
    @Attribute(.unique) private(set) var scanKey: String
    var schemaVersion: Int
    var inventoryID: UUID
    var inventoryGeneration: UUID
    var ownerID: UUID
    var recipientScanID: UUID
    var submissionGeneration: UUID
    var jobID: String
    var eventID: UUID
    var writerEpoch: UUID
    var phaseRaw: String
    var revision: Int64
    var formatRaw: String
    /// Exact canonical wrapper around the existing body and ordered hold membership.
    /// Nil is permitted only with a qualified terminal erasure receipt, never as
    /// permission to reconstruct a body from mutable drafts or queue metadata.
    var requestData: Data?
    var requestSHA256: String
    var observationSHA256: String
    var acceptanceData: Data?
    var acceptanceSHA256: String?
    /// Survives payload erasure as an identity fence against delayed retry.
    var retirementData: Data?
    var retirementSHA256: String?

    init(inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID,
         recipientScanID: UUID, submissionGeneration: UUID, jobID: String,
         eventID: UUID, writerEpoch: UUID, formatRaw: String, requestData: Data,
         requestSHA256: String, observationSHA256: String) {
        id = submissionGeneration
        cursorKey = submissionGeneration.uuidString.lowercased()
        identityKey = [ownerID, recipientScanID, submissionGeneration]
            .map { $0.uuidString.lowercased() }.joined(separator: ":")
        scanKey = [ownerID, recipientScanID].map { $0.uuidString.lowercased() }.joined(separator: ":")
        schemaVersion = 1
        self.inventoryID = inventoryID; self.inventoryGeneration = inventoryGeneration
        self.ownerID = ownerID; self.recipientScanID = recipientScanID
        self.submissionGeneration = submissionGeneration; self.jobID = jobID
        self.eventID = eventID; self.writerEpoch = writerEpoch
        phaseRaw = "reserved"; revision = 0; self.formatRaw = formatRaw
        self.requestData = requestData; self.requestSHA256 = requestSHA256
        self.observationSHA256 = observationSHA256
        acceptanceData = nil; acceptanceSHA256 = nil
        retirementData = nil; retirementSHA256 = nil
    }
}
