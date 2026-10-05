import Foundation
import SwiftData

/// Minimal local erasure authority survives private child/job deletion. Contains no photo or auth payload.
struct ObservationReanalysisErasureReceipt: Equatable, Sendable {
    let parentID: UUID
    let childID: UUID

    static func jobID(_ childID: UUID) -> String { "reanalysis-erasure:" + childID.uuidString.lowercased() }

    func record(in context: ModelContext) throws {
        if let existing = try context.fetchOfflineJob(id: Self.jobID(childID)) {
            guard try Self.restore(existing) == self else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
            return
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "parent_id": parentID.uuidString.lowercased(),
            "child_id": childID.uuidString.lowercased()], options: [.sortedKeys])
        guard parentID != childID, let text = String(bytes: data, encoding: .utf8) else { throw MerianError.invalidResponse }
        context.insert(OfflineJobRecord(id: Self.jobID(childID), kind: .observationReanalysisErasure,
            subjectId: childID.uuidString.lowercased(), status: .pending, metadataJSON: text))
    }

    static func restore(_ job: OfflineJobRecord) throws -> Self {
        guard job.kindRaw == OfflineJobKind.observationReanalysisErasure.rawValue,
              [OfflineJobStatus.pending.rawValue, OfflineJobStatus.complete.rawValue].contains(job.statusRaw),
              job.nextRunAt == nil, job.attemptCount == 0, job.lastAttemptAt == nil,
              let text = job.metadataJSON, text.utf8.count <= 512,
              let row = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              Set(row.keys) == ["version", "parent_id", "child_id"],
              let version = row["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let parent = row["parent_id"] as? String, let parentID = UUID(uuidString: parent), parentID.uuidString.lowercased() == parent,
              let child = row["child_id"] as? String, let childID = UUID(uuidString: child), childID.uuidString.lowercased() == child,
              parentID != childID, job.id == jobID(childID), job.subjectId == child else { throw MerianError.invalidResponse }
        return Self(parentID: parentID, childID: childID)
    }
}
