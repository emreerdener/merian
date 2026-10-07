import Foundation
import SwiftData

/// Minimal local erasure authority survives private child/job deletion. Contains no photo or auth payload.
struct ObservationReanalysisErasureReceipt: Equatable, Sendable {
    let parentID: UUID
    let childID: UUID
    let retirementOwnerID: UUID?
    let retirementProof: ObservationAnalysisRetirementReceipt?

    init(parentID: UUID, childID: UUID) {
        self.parentID = parentID; self.childID = childID
        retirementOwnerID = nil; retirementProof = nil
    }

    init(ownerID: UUID, retirement: ObservationAnalysisRetirementReceipt) {
        parentID = retirement.request.execution.observationID; childID = retirement.request.execution.analysisID
        retirementOwnerID = ownerID; retirementProof = retirement
    }

    /// Only parent deletion may preserve a stronger terminal proof under the same cleanup namespace.
    func recordParentErasure(in context: ModelContext) throws {
        guard retirementProof == nil else { throw MerianError.invalidResponse }
        if let existing = try context.fetchOfflineJob(id: Self.jobID(childID)) {
            let saved = try Self.restore(existing)
            guard saved.parentID == parentID, saved.childID == childID else { throw MerianError.invalidResponse }
            return
        }
        try record(in: context)
    }

    static func jobID(_ childID: UUID) -> String { "reanalysis-erasure:" + childID.uuidString.lowercased() }

    func record(in context: ModelContext) throws {
        if let existing = try context.fetchOfflineJob(id: Self.jobID(childID)) {
            guard try Self.restore(existing) == self else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
            return
        }
        var object: [String: Any] = ["version": 1, "parent_id": parentID.uuidString.lowercased(),
                                     "child_id": childID.uuidString.lowercased()]
        if let retirementProof, let retirementOwnerID {
            object["version"] = 2; object["kind"] = "retired_before_dispatch"
            object["owner_id"] = retirementOwnerID.uuidString.lowercased()
            object["receipt_base64"] = retirementProof.data.base64EncodedString()
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 8192 else { throw MerianError.invalidResponse }
        guard parentID != childID, let text = String(bytes: data, encoding: .utf8) else { throw MerianError.invalidResponse }
        context.insert(OfflineJobRecord(id: Self.jobID(childID), kind: .observationReanalysisErasure,
            subjectId: childID.uuidString.lowercased(), status: .pending, metadataJSON: text))
    }

    static func restore(_ job: OfflineJobRecord) throws -> Self {
        guard job.kindRaw == OfflineJobKind.observationReanalysisErasure.rawValue,
              [OfflineJobStatus.pending.rawValue, OfflineJobStatus.complete.rawValue].contains(job.statusRaw),
              job.nextRunAt == nil, job.attemptCount == 0, job.lastAttemptAt == nil,
              let text = job.metadataJSON, text.utf8.count <= 8192,
              let row = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let version = row["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(),
              let parent = row["parent_id"] as? String, let parentID = UUID(uuidString: parent), parentID.uuidString.lowercased() == parent,
              let child = row["child_id"] as? String, let childID = UUID(uuidString: child), childID.uuidString.lowercased() == child,
              parentID != childID, job.id == jobID(childID), job.subjectId == child else { throw MerianError.invalidResponse }
        if version.doubleValue == 1 {
            guard text.utf8.count <= 512, Set(row.keys) == ["version", "parent_id", "child_id"] else { throw MerianError.invalidResponse }
            return Self(parentID: parentID, childID: childID)
        }
        guard version.doubleValue == 2,
              Set(row.keys) == ["version", "kind", "parent_id", "child_id", "owner_id", "receipt_base64"],
              row["kind"] as? String == "retired_before_dispatch",
              let ownerText = row["owner_id"] as? String, let owner = UUID(uuidString: ownerText), owner.uuidString.lowercased() == ownerText,
              let encoded = row["receipt_base64"] as? String, let bytes = Data(base64Encoded: encoded),
              bytes.count <= 4096, bytes.base64EncodedString() == encoded,
              var receipt = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw MerianError.invalidResponse }
        receipt.removeValue(forKey: "state")
        let request = try ObservationAnalysisRetirementRequest(savedBody: JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]))
        guard request.execution.observationID == parentID, request.execution.analysisID == childID else { throw MerianError.invalidResponse }
        return try Self(ownerID: owner, retirement: .init(data: bytes, request: request))
    }
}
