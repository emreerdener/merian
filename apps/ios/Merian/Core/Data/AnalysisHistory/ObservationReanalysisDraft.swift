import Foundation

/// Offline identity and evidence, before a recipient or network request has been bound.
struct ObservationReanalysisDraft: Sendable, Equatable {
    let identity: OfflineQueueWork.Reanalysis
    let evidence: [ObservationReanalysisRequest.Evidence]

    init(identity: OfflineQueueWork.Reanalysis, evidence: [ObservationReanalysisRequest.Evidence]) throws {
        guard Set([identity.observationID, identity.analysisID, identity.sourceAnalysisID]).count == 3 else {
            throw MerianError.invalidResponse
        }
        self.evidence = try ObservationReanalysisRequest.decodeEvidence(ObservationReanalysisRequest.manifest(evidence),
            observationID: identity.observationID, analysisID: identity.analysisID)
        self.identity = identity
    }

    var photoPaths: [String] { ObservationReanalysisIntent.photoPaths(analysisID: identity.analysisID, evidence: evidence) }

    func binding(processor: IdentificationRecipientExpectation) throws -> ObservationReanalysisIntent {
        try .init(ownerID: identity.ownerID, request: .init(observationID: identity.observationID, analysisID: identity.analysisID,
            sourceAnalysisID: identity.sourceAnalysisID, processor: processor, evidence: evidence))
    }

    func storedData() throws -> Data {
        let bytes = try JSONSerialization.data(withJSONObject: [
            "version": 2, "phase": "draft", "owner_id": identity.ownerID.uuidString.lowercased(),
            "observation_id": identity.observationID.uuidString.lowercased(),
            "analysis_id": identity.analysisID.uuidString.lowercased(), "source_analysis_id": identity.sourceAnalysisID.uuidString.lowercased(),
            "evidence_manifest": try ObservationReanalysisRequest.manifest(evidence)
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= 1_044_480 else { throw MerianError.invalidResponse }
        return bytes
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_044_480,
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(row.keys) == ["version", "phase", "owner_id", "observation_id", "analysis_id", "source_analysis_id", "evidence_manifest"],
              let version = row["version"] as? NSNumber, CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 2,
              row["phase"] as? String == "draft",
              let owner = uuid(row["owner_id"]), let observation = uuid(row["observation_id"]),
              let analysis = uuid(row["analysis_id"]), let source = uuid(row["source_analysis_id"]) else { throw MerianError.invalidResponse }
        return try Self(identity: .init(observationID: observation, sourceAnalysisID: source, analysisID: analysis, ownerID: owner),
            evidence: ObservationReanalysisRequest.decodeEvidence(row["evidence_manifest"], observationID: observation, analysisID: analysis))
    }

    private static func uuid(_ value: Any?) -> UUID? {
        guard let text = value as? String, let id = UUID(uuidString: text), id.uuidString.lowercased() == text else { return nil }
        return id
    }
}
