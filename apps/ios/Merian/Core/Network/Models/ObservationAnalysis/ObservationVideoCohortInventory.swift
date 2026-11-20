import Foundation

/// Held metadata only; not a receipt, readiness proof or upload/execution capability.
struct ObservationVideoCohortInventory: Equatable, Sendable {
    enum Role: String, Sendable { case source, frame, audio }
    struct Item: Equatable, Sendable {
        let role: Role
        let index: Int?
        let artifact: ObservationVideoProvenance.Artifact
    }
    let items: [Item]

    init(input: Data) throws {
        // Uses semantic replay identity, not native saved-body digest restoration.
        _ = try ObservationVideoSourceFingerprint(input: input)
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: input), keys: [
            "schema_version", "observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest",
            "entitlement_protocol", "identification_protocol", "history_protocol", "expected_processor_permission"
        ])
        let manifestRow = try ObservationHistoryPage.object(row["evidence_manifest"], keys: ["schema_version", "provenance", "descriptions"])
        let manifest = try ObservationVideoManifest(
            data: JSONSerialization.data(withJSONObject: manifestRow),
            observationID: ObservationHistoryPage.uuid(row["observation_id"]),
            analysisID: ObservationHistoryPage.uuid(row["analysis_id"]))
        let graph = manifest.provenance
        items = [Item(role: .source, index: nil, artifact: graph.source)]
            + graph.frames.map { Item(role: .frame, index: $0.index, artifact: $0.artifact) }
            + (graph.audio.map { [Item(role: .audio, index: nil, artifact: $0.artifact)] } ?? [])
    }

    /// Exact whole-array coverage. No independent acknowledgement can establish it.
    func validate(items data: Data) throws {
        guard !data.isEmpty, data.count <= 4096,
              let rows = try JSONSerialization.jsonObject(with: data) as? [Any],
              rows.count == items.count else { throw MerianError.invalidResponse }
        for (value, expected) in zip(rows, items) {
            let row = try ObservationHistoryPage.object(value, keys: ["role", "index", "media_id", "content_type", "byte_count", "sha256"])
            let index: Int?
            if row["index"] is NSNull { index = nil } else { index = try ObservationHistoryPage.integer(row["index"]) }
            guard row["role"] as? String == expected.role.rawValue, index == expected.index,
                  try ObservationHistoryPage.uuid(row["media_id"]) == expected.artifact.mediaID,
                  row["content_type"] as? String == expected.artifact.contentType,
                  try ObservationHistoryPage.integer(row["byte_count"]) == expected.artifact.byteCount,
                  row["sha256"] as? String == expected.artifact.sha256 else { throw MerianError.invalidResponse }
        }
    }
}
