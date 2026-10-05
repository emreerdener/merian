import CryptoKit
import Foundation

/// Immutable protocol-8 photo reanalysis input, saved before its first network operation.
/// Restoration validates the original bytes; it never creates another analysis identity.
struct ObservationReanalysisRequest: Sendable, Equatable {
    enum Evidence: Sendable, Equatable {
        case image(ObservationEvidenceUpload.Reference)
        case description(String)
    }

    let observationID: UUID
    let analysisID: UUID
    let sourceAnalysisID: UUID
    let processor: IdentificationRecipientExpectation
    let evidence: [Evidence]
    let body: Data

    init(observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID,
         processor: IdentificationRecipientExpectation, evidence: [Evidence]) throws {
        var row: [String: Any] = [
            "schema_version": 2, "observation_id": observationID.uuidString.lowercased(),
            "analysis_id": analysisID.uuidString.lowercased(),
            "source_analysis_id": sourceAnalysisID.uuidString.lowercased(),
            "entitlement_protocol": 3, "identification_protocol": 6, "history_protocol": 8,
            "expected_processor_permission": processor.rawValue,
            "evidence_manifest": try Self.manifest(evidence)
        ]
        row["request_digest"] = try Self.digest(row)
        try self.init(savedBody: Self.canonical(row))
    }

    /// Canonicalization version is this type's schema-2 native contract. Saved bytes win on replay.
    init(savedBody: Data) throws {
        guard savedBody.count <= 1_044_480,
              let row = try JSONSerialization.jsonObject(with: savedBody) as? [String: Any],
              Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "source_analysis_id",
                                "request_digest", "evidence_manifest", "entitlement_protocol",
                                "identification_protocol", "history_protocol", "expected_processor_permission"],
              Self.integer(row["schema_version"]) == 2,
              Self.integer(row["entitlement_protocol"]) == 3,
              Self.integer(row["identification_protocol"]) == 6,
              Self.integer(row["history_protocol"]) == 8,
              let observation = Self.uuid(row["observation_id"]),
              let analysis = Self.uuid(row["analysis_id"]),
              let source = Self.uuid(row["source_analysis_id"]),
              Set([observation, analysis, source]).count == 3,
              let rawProcessor = row["expected_processor_permission"] as? String,
              let processor = IdentificationRecipientExpectation(rawValue: rawProcessor), processor != .recoveryOnly else {
            throw MerianError.invalidResponse
        }
        var unsigned = row
        unsigned.removeValue(forKey: "request_digest")
        guard let digest = row["request_digest"] as? String, digest == (try Self.digest(unsigned)) else {
            throw MerianError.invalidResponse
        }
        self.evidence = try Self.decodeEvidence(row["evidence_manifest"], observationID: observation, analysisID: analysis)
        self.observationID = observation; self.analysisID = analysis; self.sourceAnalysisID = source
        self.processor = processor; self.body = savedBody
    }

    /// Shared with the offline draft: evidence validation never needs an invented recipient.
    static func manifest(_ evidence: [Evidence]) throws -> [String: Any] {
        ["schema_version": 2, "items": try evidence.map { item -> [String: Any] in
            switch item {
            case let .description(text): return ["kind": "description", "text": text]
            case let .image(reference):
                guard let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reference)) as? [String: Any] else {
                    throw MerianError.invalidResponse
                }
                return row
            }
        }]
    }

    static func decodeEvidence(_ value: Any?, observationID observation: UUID, analysisID analysis: UUID) throws -> [Evidence] {
        guard let manifest = value as? [String: Any],
              Set(manifest.keys) == ["schema_version", "items"], Self.integer(manifest["schema_version"]) == 2,
              let items = manifest["items"] as? [[String: Any]], (1...64).contains(items.count) else {
            throw MerianError.invalidResponse
        }
        var evidence: [Evidence] = [], seen = Set<UUID>(), totalBytes = 0, totalText = 0
        for item in items {
            if item["kind"] as? String == "description" {
                guard Set(item.keys) == ["kind", "text"], let text = item["text"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      text.unicodeScalars.count <= 8192, text.utf16.count <= 16384,
                      text.utf16.count <= 32000 - totalText else { throw MerianError.invalidResponse }
                totalText += text.utf16.count
                evidence.append(.description(text))
            } else {
                guard Set(item.keys) == ["kind", "media_id", "content_type", "byte_count", "sha256"],
                      item["kind"] as? String == "image", let media = Self.uuid(item["media_id"]),
                      media != observation, media != analysis, seen.insert(media).inserted, seen.count <= 5,
                      let contentType = item["content_type"] as? String, ["image/jpeg", "image/png"].contains(contentType),
                      let count = Self.integer(item["byte_count"]), count > 0,
                      count <= ObservationEvidenceUpload.maximumBytes - totalBytes,
                      let sha = item["sha256"] as? String, sha.count == 64,
                      sha.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                    throw MerianError.invalidResponse
                }
                totalBytes += count
                evidence.append(.image(.init(mediaID: media, contentType: contentType, byteCount: count, sha256: sha)))
            }
        }
        guard !seen.isEmpty else { throw MerianError.invalidResponse }
        return evidence
    }

    private static func canonical(_ row: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private static func digest(_ row: [String: Any]) throws -> String {
        SHA256.hash(data: try canonical(row)).map { String(format: "%02x", $0) }.joined()
    }
    private static func uuid(_ value: Any?) -> UUID? {
        guard let text = value as? String, let uuid = UUID(uuidString: text), uuid.uuidString.lowercased() == text else { return nil }
        return uuid
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= Double(ObservationEvidenceUpload.maximumBytes),
              Double(number.intValue) == number.doubleValue else { return nil }
        return number.intValue
    }
}
