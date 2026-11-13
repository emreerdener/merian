import CryptoKit
import Foundation

/// A device's acknowledged saved display, never reconstructed provider output.
/// This envelope is local-only and cannot supply missing evidence on another device.
enum SavedIdentificationDisplayBaseline {
    static func capture(_ display: AnalysisDisplaySnapshot, matching result: ObservationHistoryPage.Result) throws -> Data? {
        guard result.version == 3, result.analysisID == display.analysisID,
              let envelope = try JSONSerialization.jsonObject(with: result.bytes) as? [String: Any],
              let saved = envelope["result"] as? [String: Any],
              let confidence = saved["ai_confidence_score"] as? Double,
              confidence == display.confidenceScore,
              (saved["is_biological_subject"] as? Bool) == display.isBiological,
              (saved["ai_reasoning"] as? String) == display.aiReasoning,
              (saved["inference_tier"] as? String) == display.inferenceTier else { return nil }
        if saved["species_id"] is NSNull {
            guard display.speciesId.isEmpty else { return nil }
        } else {
            guard let identifier = saved["species_id"] as? String,
                  let expected = UUID(uuidString: identifier), UUID(uuidString: display.speciesId) == expected else { return nil }
        }
        for (key, bytes) in [("primary_identification", display.primaryIdentificationData),
                             ("identification_provenance", display.identificationProvenanceData),
                             ("candidates", display.candidatesData), ("pet_identification", display.petIdentificationData)] {
            guard let expected = saved[key], matchesJSON(bytes, expected) else { return nil }
        }
        // A local display may itself exceed the limit or contain non-JSON
        // values. Neither can establish a baseline or block authority sync.
        guard let displayData = try? display.storedData() else { return nil }
        let object: [String: Any] = ["schema_version": 1, "origin": "saved_local_projection", "source_result_version": 3,
            "display": try JSONSerialization.jsonObject(with: displayData)]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        // Optional display must not prevent durable result/authority admission.
        guard data.count <= LocalAnalysisRecord.maximumSnapshotBytes else { return nil }
        return data
    }

    /// First enrollment only: the caller revalidates the retained same-owner
    /// completion proof inside its final account/deletion-fenced transaction.
    /// Local dictionary UUIDs are not server taxonomy IDs. Keep both identities
    /// and the immutable server bytes. The original completion hash is retained
    /// provenance, not a signature or a revalidation after the job is removed.
    static func captureOrdinary(_ display: AnalysisDisplaySnapshot, matching result: ObservationHistoryPage.Result,
                                proof: OrdinaryInferenceCompletion.Proof, owner: UUID) throws -> Data? {
        guard proof.version == 1, proof.ownerID == owner, proof.speciesID == display.speciesId,
              try OrdinaryInferenceCompletion.Projection(display) == proof.projection,
              let envelope = try JSONSerialization.jsonObject(with: result.bytes) as? [String: Any],
              envelope["observation_id"] as? String == proof.scanID.uuidString.lowercased(),
              matchesOrdinaryDisplay(display, result: result) else { return nil }
        let object: [String: Any] = ["schema_version": 2, "origin": "ordinary_completion_local_projection",
            "source_result_version": 3, "source_result_sha256": digest(result.bytes),
            "original_completion_sha256": proof.resultSHA256,
            "display": try JSONSerialization.jsonObject(with: display.storedData())]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.count <= LocalAnalysisRecord.maximumSnapshotBytes ? data : nil
    }

    static func restoreMatching(_ data: Data, result: ObservationHistoryPage.Result) throws -> AnalysisDisplaySnapshot {
        guard data.count <= LocalAnalysisRecord.maximumSnapshotBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ObservationHistoryError.invalidSnapshot
        }
        if object["schema_version"] as? Int == 1 {
            let display = try restore(data, analysisID: result.analysisID)
            guard try capture(display, matching: result) == data else { throw ObservationHistoryError.resultConflict }
            return display
        }
        let row = try ObservationHistoryPage.object(object, keys: ["schema_version", "origin", "source_result_version",
            "source_result_sha256", "original_completion_sha256", "display"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 2,
              try ObservationHistoryPage.integer(row["source_result_version"]) == 3,
              row["origin"] as? String == "ordinary_completion_local_projection",
              row["source_result_sha256"] as? String == digest(result.bytes),
              let original = row["original_completion_sha256"] as? String, original.count == 64,
              original.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let value = row["display"] as? [String: Any] else { throw ObservationHistoryError.resultConflict }
        let display = try AnalysisDisplaySnapshot.restore(JSONSerialization.data(withJSONObject: value), analysisID: result.analysisID)
        guard matchesOrdinaryDisplay(display, result: result) else { throw ObservationHistoryError.resultConflict }
        return display
    }

    private static func matchesOrdinaryDisplay(_ display: AnalysisDisplaySnapshot, result: ObservationHistoryPage.Result) -> Bool {
        guard result.version == 3, result.analysisID == display.analysisID,
              let envelope = try? JSONSerialization.jsonObject(with: result.bytes) as? [String: Any],
              let saved = envelope["result"] as? [String: Any],
              saved["ai_confidence_score"] as? Double == display.confidenceScore,
              saved["is_biological_subject"] as? Bool == display.isBiological,
              saved["ai_reasoning"] as? String == display.aiReasoning,
              saved["inference_tier"] as? String == display.inferenceTier else { return false }
        if saved["species_id"] is NSNull {
            guard display.speciesId.isEmpty else { return false }
        } else {
            guard let serverID = saved["species_id"] as? String,
                  UUID(uuidString: serverID) != nil, UUID(uuidString: display.speciesId) != nil else { return false }
        }
        for (key, bytes) in [("primary_identification", display.primaryIdentificationData),
                             ("identification_provenance", display.identificationProvenanceData),
                             ("pet_identification", display.petIdentificationData)] {
            guard let expected = saved[key], matchesJSON(bytes, expected) else { return false }
        }
        if saved["candidates"] is NSNull { return display.candidatesData == nil }
        guard let candidates = saved["candidates"], let local = display.candidatesData else { return false }
        do {
            // Same ordered, explicit wire-to-domain mapping as ordinary inference.
            let wire = try JSONDecoder().decode([EdgeResponse.IdentificationCandidate].self,
                from: JSONSerialization.data(withJSONObject: candidates))
            let mapped = wire.map { IdentificationCandidate(scientificName: $0.scientific_name,
                commonName: $0.common_name?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
                confidenceScore: $0.confidence_score, distinguishingFeature: $0.distinguishing_feature) }
            return matchesJSON(local, try JSONSerialization.jsonObject(with: JSONEncoder().encode(mapped)))
        } catch { return false }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func restore(_ data: Data, analysisID: UUID) throws -> AnalysisDisplaySnapshot {
        guard data.count <= LocalAnalysisRecord.maximumSnapshotBytes else { throw ObservationHistoryError.invalidSnapshot }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data),
            keys: ["schema_version", "origin", "source_result_version", "display"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1,
              try ObservationHistoryPage.integer(row["source_result_version"]) == 3,
              row["origin"] as? String == "saved_local_projection" else { throw ObservationHistoryError.invalidSnapshot }
        guard let object = row["display"] as? [String: Any] else { throw ObservationHistoryError.invalidSnapshot }
        let display = try JSONSerialization.data(withJSONObject: object)
        return try AnalysisDisplaySnapshot.restore(display, analysisID: analysisID)
    }

    private static func matchesJSON(_ bytes: Data?, _ expected: Any) -> Bool {
        do {
            let value: Any = try bytes.map { try JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) } ?? NSNull()
            let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .sortedKeys]
            return try JSONSerialization.data(withJSONObject: value, options: options) ==
                JSONSerialization.data(withJSONObject: expected, options: options)
        } catch {
            // Malformed legacy local bytes cannot establish a display baseline.
            return false
        }
    }
}
