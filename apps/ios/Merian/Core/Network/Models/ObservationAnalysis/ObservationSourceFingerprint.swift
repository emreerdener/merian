import CryptoKit
import Foundation

/// Pure metadata binding. This does not restore a saved request, establish ownership or admit work.
/// The legacy digest stays a replay identifier; no JSON digest is reconstructed or rewritten.
struct ObservationSourceFingerprint: Sendable, Equatable {
    static let maximumBytes = 262_144
    let canonicalBytes: Data
    let sha256: String

    init(input: Data) throws {
        guard input.count <= 1_044_480,
              let row = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "source_analysis_id",
                                "request_digest", "evidence_manifest", "entitlement_protocol", "identification_protocol",
                                "history_protocol", "expected_processor_permission"] else { throw MerianError.invalidResponse }
        let version = try Self.integer(row["schema_version"])
        guard [2, 3].contains(version), try Self.integer(row["entitlement_protocol"]) == 3,
              try Self.integer(row["identification_protocol"]) == 6,
              try Self.integer(row["history_protocol"]) == (version == 2 ? 8 : 9),
              let processor = row["expected_processor_permission"] as? String,
              (version == 2 ? ["google_gemini", "openai"] : ["google_gemini"]).contains(processor) else {
            throw MerianError.invalidResponse
        }
        let observation = try ObservationHistoryPage.uuid(row["observation_id"])
        let analysis = try ObservationHistoryPage.uuid(row["analysis_id"])
        let source = try ObservationHistoryPage.uuid(row["source_analysis_id"])
        guard Set([observation, analysis, source]).count == 3,
              let digest = row["request_digest"] as? String, Self.isDigest(digest),
              let manifest = row["evidence_manifest"] as? [String: Any], Set(manifest.keys) == ["schema_version", "items"],
              try Self.integer(manifest["schema_version"]) == version,
              let items = manifest["items"] as? [[String: Any]], (1...64).contains(items.count) else {
            throw MerianError.invalidResponse
        }
        var fields = ["merian.analysis-source-reservation", "1", String(version), observation.uuidString.lowercased(),
                      analysis.uuidString.lowercased(), source.uuidString.lowercased(), digest, "3", "6",
                      version == 2 ? "8" : "9", processor, version == 2 ? "multimodal_photo_v1" : "multimodal_audio_v1",
                      String(version), String(items.count)]
        var mediaIDs = Set<UUID>(), bytes = 0, textUnits = 0
        for item in items {
            if item["kind"] as? String == "description" {
                guard Set(item.keys) == ["kind", "text"], let text = item["text"] as? String,
                      text.unicodeScalars.count <= 8192, text.utf16.count <= 16384,
                      text.utf16.count <= 32000 - textUnits,
                      ObservationHistoryAudioReference.hasDescriptionContent(text) else {
                    throw MerianError.invalidResponse
                }
                textUnits += text.utf16.count
                fields += ["description", text]
            } else {
                guard Set(item.keys) == ["kind", "media_id", "content_type", "byte_count", "sha256"],
                      item["kind"] as? String == (version == 2 ? "image" : "audio"),
                      let contentType = item["content_type"] as? String,
                      (version == 2 ? ["image/jpeg", "image/png"] : ["audio/wav"]).contains(contentType),
                      let sha = item["sha256"] as? String, Self.isDigest(sha) else { throw MerianError.invalidResponse }
                let media = try ObservationHistoryPage.uuid(item["media_id"])
                let count = try Self.integer(item["byte_count"])
                let maximum = version == 2 ? 5 * 1024 * 1024 : 2_700_000
                guard ![observation, analysis, source].contains(media), mediaIDs.insert(media).inserted,
                      mediaIDs.count <= (version == 2 ? 5 : 1), count >= (version == 2 ? 1 : 46),
                      count <= maximum - bytes else { throw MerianError.invalidResponse }
                bytes += count
                fields += [version == 2 ? "image" : "audio", media.uuidString.lowercased(), contentType, String(count), sha]
            }
        }
        guard !mediaIDs.isEmpty else { throw MerianError.invalidResponse }
        var framed = Data()
        for field in fields {
            guard !field.unicodeScalars.contains(where: { $0.value == 0 }) else { throw MerianError.invalidResponse }
            let value = Data(field.utf8)
            let prefix = Data("\(value.count):".utf8)
            guard value.count + prefix.count + 1 <= Self.maximumBytes - framed.count else { throw MerianError.invalidResponse }
            framed.append(prefix); framed.append(value); framed.append(0x2c)
        }
        canonicalBytes = framed
        sha256 = SHA256.hash(data: framed).map { String(format: "%02x", $0) }.joined()
    }

    private static func integer(_ value: Any?) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= 5 * 1024 * 1024,
              Double(number.intValue) == number.doubleValue else { throw MerianError.invalidResponse }
        return number.intValue
    }
    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
