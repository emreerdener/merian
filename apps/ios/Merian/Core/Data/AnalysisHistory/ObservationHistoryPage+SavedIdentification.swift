import CoreFoundation
import Foundation

extension ObservationHistoryPage {
    /// A surviving saved identification has no reconstructed provider execution.
    /// Its import date must never stand in for a missing completion date.
    static func importedSnapshot(_ row: [String: Any], bytes: Data, observationID: String, analysisID: UUID, ordinal: Int) throws -> Result {
        let manifest = try object(row["evidence_manifest"], keys: ["schema_version", "origin", "imported_at_ms", "availability"])
        guard ordinal == 1, row["source_analysis_id"] is NSNull,
              row["request_digest"] is NSNull, row["completed_at_ms"] is NSNull,
              try integer(manifest["schema_version"]) == 3,
              manifest["origin"] as? String == "saved_identification",
              manifest["availability"] as? String == "unavailable" else {
            throw ObservationHistoryError.invalidSnapshot
        }
        let milliseconds = try integer(manifest["imported_at_ms"], maximum: 8_640_000_000_000_000)
        let saved = try object(row["result"], keys: ["scan_id", "primary_identification", "identification_provenance",
            "species_id", "is_biological_subject", "candidates", "pet_identification", "ai_confidence_score", "ai_reasoning", "inference_tier"])
        guard saved["scan_id"] as? String == observationID,
              let confidence = saved["ai_confidence_score"] as? NSNumber,
              CFGetTypeID(confidence) != CFBooleanGetTypeID(), confidence.doubleValue.isFinite,
              (0...1).contains(confidence.doubleValue),
              saved["ai_reasoning"] is NSNull || saved["ai_reasoning"] is String,
              saved["inference_tier"] is NSNull || saved["inference_tier"] is String else {
            throw ObservationHistoryError.invalidSnapshot
        }
        if !(saved["species_id"] is NSNull) { _ = try uuid(saved["species_id"]) }
        if !(saved["is_biological_subject"] is NSNull) {
            guard let biological = saved["is_biological_subject"] as? NSNumber,
                  CFGetTypeID(biological) == CFBooleanGetTypeID() else { throw ObservationHistoryError.invalidSnapshot }
        }
        let primary = try savedValue(PrimaryIdentificationDTO.self, saved["primary_identification"])
        let provenance = try savedValue(IdentificationProvenanceDTO.self, saved["identification_provenance"])
        guard (primary != nil) == PrimaryIdentificationProvenancePolicy.requiresSnapshot(provenance),
              primary.map({ PrimaryIdentification(dto: $0).value != nil }) ?? true else {
            throw ObservationHistoryError.invalidSnapshot
        }
        // Legacy candidate/pet JSON remains opaque. It predates the provider DTO
        // and is neither review authority nor input to another inference.
        return Result(version: 3, photos: [], audio: nil, video: nil, analysisID: analysisID, completedAt: nil,
            importedAt: Date(timeIntervalSince1970: Double(milliseconds) / 1000), bytes: bytes)
    }

    private static func savedValue<T: Decodable>(_ type: T.Type, _ value: Any?) throws -> T? {
        guard let value else { throw ObservationHistoryError.invalidSnapshot }
        if value is NSNull { return nil }
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
    }
}
