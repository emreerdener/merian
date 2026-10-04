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
