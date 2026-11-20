import Foundation

/// An ownership/import receipt, never proof of current selection or authority.
struct ObservationHistoryEnrollment {
    let baselineAnalysisID: UUID

    static func decode(_ data: Data, observationID: UUID, ownerID: UUID) throws -> Self {
        guard data.count <= 4096 else { throw ObservationHistoryError.invalidPage }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data),
            keys: ["schema_version", "owner_id", "observation_id", "baseline_analysis_id"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              try ObservationHistoryPage.uuid(row["owner_id"]) == ownerID,
              try ObservationHistoryPage.uuid(row["observation_id"]) == observationID else {
            throw ObservationHistoryError.invalidPage
        }
        let baseline = try ObservationHistoryPage.uuid(row["baseline_analysis_id"])
        guard baseline != ownerID, baseline != observationID else { throw ObservationHistoryError.invalidPage }
        return Self(baselineAnalysisID: baseline)
    }
}

/// Recovery of existing server evidence, never enrollment or selected authority.
struct ObservationHistoryBaselineRecovery {
    let enrollment: ObservationHistoryEnrollment
    let result: ObservationHistoryPage.Result
    let snapshotSHA256: String

    private init(enrollment: ObservationHistoryEnrollment, result: ObservationHistoryPage.Result, snapshotSHA256: String) {
        self.enrollment = enrollment; self.result = result; self.snapshotSHA256 = snapshotSHA256
    }

    static func decode(_ data: Data, observationID: UUID, ownerID: UUID) throws -> Self {
        guard data.count <= 4_194_304 else { throw ObservationHistoryError.invalidPage }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data),
            keys: ["schema_version", "owner_id", "observation_id", "baseline_analysis_id", "snapshot", "snapshot_sha256"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              try ObservationHistoryPage.uuid(row["owner_id"]) == ownerID,
              try ObservationHistoryPage.uuid(row["observation_id"]) == observationID,
              let text = row["snapshot"] as? String, text.utf8.count <= LocalAnalysisRecord.maximumSnapshotBytes,
              let hash = row["snapshot_sha256"] as? String,
              hash == ObservationHistoryEnrollmentIntent.baselineDigest(Data(text.utf8)) else {
            throw ObservationHistoryError.invalidPage
        }
        let baseline = try ObservationHistoryPage.uuid(row["baseline_analysis_id"])
        let result = try ObservationHistoryPage.snapshot(Data(text.utf8), observationID: observationID.uuidString.lowercased(), ordinal: 1)
        guard baseline != observationID, baseline != ownerID, result.version == 3, result.analysisID == baseline else {
            throw ObservationHistoryError.invalidPage
        }
        return Self(enrollment: .init(baselineAnalysisID: baseline), result: result, snapshotSHA256: hash)
    }
}

/// One server observation fence binds original import and current selection.
struct ObservationHistoryEnrollmentSelection {
    let baseline: ObservationHistoryState
    let selected: ObservationHistoryState

    static func decode(_ data: Data, observation: UUID, owner: UUID, receipt: ObservationHistoryEnrollment) throws -> Self {
        guard data.count <= ObservationHistoryPage.maximumPageBytes else { throw ObservationHistoryError.invalidPage }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data),
            keys: ["schema_version", "baseline_sha256", "baseline_state", "selected_state"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              let baselineObject = row["baseline_state"] as? [String: Any],
              let selectedObject = row["selected_state"] as? [String: Any] else { throw ObservationHistoryError.invalidPage }
        let request = ObservationHistoryStateRequest(observation_id: observation.uuidString.lowercased(), analysis_id: receipt.baselineAnalysisID.uuidString.lowercased())
        let baseline = try ObservationHistoryState.decode(JSONSerialization.data(withJSONObject: baselineObject), request: request, ownerID: owner)
        let selected = try ObservationHistoryState.decode(JSONSerialization.data(withJSONObject: selectedObject),
            request: .init(observation_id: request.observation_id, analysis_id: nil), ownerID: owner)
        guard baseline.revision == selected.revision, baseline.selectedAnalysisID == selected.selectedAnalysisID,
              let text = String(data: baseline.result.bytes, encoding: .utf8) else { throw ObservationHistoryError.invalidPage }
        _ = try ObservationHistoryBaselineRecovery.decode(JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "owner_id": owner.uuidString.lowercased(), "observation_id": request.observation_id,
            "baseline_analysis_id": receipt.baselineAnalysisID.uuidString.lowercased(), "snapshot": text,
            "snapshot_sha256": row["baseline_sha256"]!
        ]), observationID: observation, ownerID: owner)
        if baseline.result.analysisID == selected.result.analysisID {
            guard baseline.result.bytes == selected.result.bytes, baseline.reviewRevision == selected.reviewRevision,
                  baseline.review.data == selected.review.data else { throw ObservationHistoryError.invalidPage }
        }
        return .init(baseline: baseline, selected: selected)
    }
}
