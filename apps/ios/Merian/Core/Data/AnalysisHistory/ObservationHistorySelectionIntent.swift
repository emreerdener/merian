import Foundation
import SwiftData

/// One pending request or latest acknowledged receipt per observation. Caller
/// owns the shared transaction, account/deletion checks, save and rollback.
enum ObservationHistorySelectionIntent {
    static let prefix = "observation-history-selection:"
    enum Failure: Error, Equatable { case invalidIntent, pendingSelection, staleUndo }

    struct Entry: Codable, Equatable {
        let version: Int
        let owner: String
        let previous: String
        let previousReview: Int
        let request: ObservationHistorySelectionRequest
        var receipt: ObservationHistorySelectionReceipt?
        var rejection: ObservationHistorySelectionRejection?
    }

    static func jobID(_ observation: String) -> String { prefix + observation.lowercased() }

    static func load(_ observation: String, context: ModelContext) throws -> Entry? {
        guard let job = try context.fetchOfflineJob(id: jobID(observation)) else { return nil }
        guard job.kindRaw == OfflineJobKind.future.rawValue, job.subjectId == observation.lowercased(),
              job.nextRunAt == nil, let text = job.metadataJSON, text.utf8.count <= 8_192 else { throw Failure.invalidIntent }
        let data = Data(text.utf8)
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == Set(["version", "owner", "previous", "previousReview", "request"] + (row["receipt"] == nil ? [] : ["receipt"]) + (row["rejection"] == nil ? [] : ["rejection"])) else {
            throw Failure.invalidIntent
        }
        _ = try ObservationHistoryPage.object(row["request"], keys: ["schema_version", "observation_id", "analysis_id",
            "operation_id", "expected_observation_revision", "expected_review_revision"])
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        try entry.request.validate()
        _ = try ObservationHistoryPage.uuid(entry.owner)
        _ = try ObservationHistoryPage.uuid(entry.previous)
        guard (entry.version == 1 || entry.version == 2), entry.request.observation_id == observation.lowercased(),
              entry.previous != observation.lowercased(), entry.previous != entry.request.analysis_id,
              entry.previousReview >= 0, entry.previousReview <= entry.request.expected_observation_revision else { throw Failure.invalidIntent }
        if entry.rejection != nil {
            guard entry.version == 2, entry.receipt == nil, row["receipt"] == nil,
                  job.statusRaw == OfflineJobStatus.cancelled.rawValue else { throw Failure.invalidIntent }
            _ = try ObservationHistorySelectionRejection.decode(JSONSerialization.data(withJSONObject: row["rejection"]!), request: entry.request)
        } else if let receipt = entry.receipt {
            guard row["rejection"] == nil else { throw Failure.invalidIntent }
            guard job.statusRaw == OfflineJobStatus.complete.rawValue else { throw Failure.invalidIntent }
            _ = try ObservationHistorySelectionReceipt.decode(JSONSerialization.data(withJSONObject: row["receipt"]!),
                request: entry.request, previous: entry.previous)
            guard receipt.observation_revision > entry.request.expected_observation_revision else { throw Failure.invalidIntent }
        } else {
            guard job.statusRaw == OfflineJobStatus.needsAttention.rawValue, row["receipt"] == nil, row["rejection"] == nil else { throw Failure.invalidIntent }
        }
        return entry
    }

    static func requireIdle(_ observation: String, context: ModelContext) throws {
        if let entry = try load(observation, context: context), entry.receipt == nil, entry.rejection == nil { throw Failure.pendingSelection }
    }

    static func store(_ entry: Entry, context: ModelContext) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(entry)
        guard data.count <= 8_192, let text = String(data: data, encoding: .utf8) else { throw Failure.invalidIntent }
        let id = jobID(entry.request.observation_id)
        let job: OfflineJobRecord
        if let existing = try context.fetchOfflineJob(id: id) { job = existing } else {
            job = OfflineJobRecord(id: id, kind: .future, subjectId: entry.request.observation_id, status: .needsAttention)
            context.insert(job)
        }
        job.metadataJSON = text
        job.status = entry.rejection != nil ? .cancelled : (entry.receipt == nil ? .needsAttention : .complete)
        job.nextRunAt = nil
        job.updatedAt = Date()
    }

    static func removeForDeletion(_ observation: String, context: ModelContext) throws {
        if let job = try context.fetchOfflineJob(id: jobID(observation)) { context.delete(job) }
    }
}
