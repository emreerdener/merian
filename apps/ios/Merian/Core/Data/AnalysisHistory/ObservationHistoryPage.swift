import CoreFoundation
import Foundation

enum ObservationHistoryError: Error, Equatable {
    case invalidPage, invalidSnapshot, unavailable, accountChanged, deleted, resultConflict
}

struct ObservationHistoryPageRequest: Encodable {
    let schema_version = 1
    let observation_id: String
    let before_ordinal: Int?
    let limit: Int

    enum CodingKeys: String, CodingKey { case schema_version, observation_id, before_ordinal, limit }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schema_version, forKey: .schema_version)
        try values.encode(observation_id, forKey: .observation_id)
        try values.encode(before_ordinal, forKey: .before_ordinal)
        try values.encode(limit, forKey: .limit)
    }
}

/// Only the decoder constructs admitted values. Raw response bytes never become models directly.
struct ObservationHistoryPage {
    struct Result {
        let version: Int
        let photos: [ObservationHistoryPhotoReference]
        let audio: ObservationHistoryAudioReference?
        let video: ObservationVideoManifest?
        let analysisID: UUID
        let completedAt: Date?
        let importedAt: Date?
        let bytes: Data
    }
    let ownerID: UUID
    let observationID: String
    let results: [Result]
    let revision: Int
    let nextBeforeOrdinal: Int?
    static let maximumPageBytes = 4_194_304

    private init(ownerID: UUID, observationID: String, results: [Result], nextBeforeOrdinal: Int?, revision: Int) {
        self.ownerID = ownerID; self.observationID = observationID
        self.results = results; self.nextBeforeOrdinal = nextBeforeOrdinal; self.revision = revision
    }

    static func decode(_ data: Data, request: ObservationHistoryPageRequest, ownerID: UUID) throws -> Self {
        guard data.count <= maximumPageBytes, (1...20).contains(request.limit),
              request.before_ordinal.map({ (1...2_147_483_646).contains($0) }) ?? true else {
            throw ObservationHistoryError.invalidPage
        }
        _ = try uuid(request.observation_id)
        let page = try object(JSONSerialization.jsonObject(with: data), keys:
            ["schema_version", "owner_id", "observation_id", "state_revision", "items", "next_before_ordinal"])
        guard try integer(page["schema_version"]) == 1,
              try uuid(page["owner_id"]) == ownerID,
              page["observation_id"] as? String == request.observation_id,
              let items = page["items"] as? [Any], items.count <= request.limit else {
            throw ObservationHistoryError.invalidPage
        }
        let revision = try integer(page["state_revision"])
        var previous = request.before_ordinal ?? 2_147_483_647
        var seen = Set<UUID>()
        let results = try items.map { item -> Result in
            let item = try object(item, keys: ["ordinal", "snapshot"])
            let ordinal = try integer(item["ordinal"])
            guard ordinal > 0, ordinal < previous, let text = item["snapshot"] as? String else {
                throw ObservationHistoryError.invalidPage
            }
            let result = try snapshot(Data(text.utf8), observationID: request.observation_id, ordinal: ordinal)
            guard seen.insert(result.analysisID).inserted else { throw ObservationHistoryError.invalidPage }
            previous = ordinal
            return result
        }
        let next = page["next_before_ordinal"] is NSNull ? nil : try integer(page["next_before_ordinal"])
        guard next == nil || (!results.isEmpty && next == previous && previous > 1) else {
            throw ObservationHistoryError.invalidPage
        }
        return Self(ownerID: ownerID, observationID: request.observation_id, results: results, nextBeforeOrdinal: next, revision: revision)
    }

    static func snapshot(_ bytes: Data, observationID: String, ordinal: Int) throws -> Result {
        guard bytes.count <= LocalAnalysisRecord.maximumSnapshotBytes else { throw ObservationHistoryError.invalidSnapshot }
        let row = try object(JSONSerialization.jsonObject(with: bytes), keys:
            ["schema_version", "observation_id", "analysis_id", "source_analysis_id", "request_digest", "ordinal", "completed_at_ms", "result", "evidence_manifest"])
        let analysisID = try uuid(row["analysis_id"])
        let observationUUID = try uuid(observationID)
        let version = try integer(row["schema_version"])
        guard [1, 2, 3, 4, 5].contains(version), row["observation_id"] as? String == observationID,
              analysisID != observationUUID,
              try integer(row["ordinal"]) == ordinal else {
            throw ObservationHistoryError.invalidSnapshot
        }
        if version == 3 {
            return try importedSnapshot(row, bytes: bytes, observationID: observationID, analysisID: analysisID, ordinal: ordinal)
        }
        guard let digest = row["request_digest"] as? String,
              digest.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw ObservationHistoryError.invalidSnapshot
        }
        if !(row["source_analysis_id"] is NSNull) {
            let sourceID = try uuid(row["source_analysis_id"])
            guard sourceID != analysisID, sourceID != observationUUID else {
                throw ObservationHistoryError.invalidSnapshot
            }
        }
        let milliseconds = try integer(row["completed_at_ms"], maximum: 8_640_000_000_000_000)
        guard let resultObject = row["result"] as? [String: Any],
              Set(["scan_id", "is_biological_subject", "is_live_capture", "confidence_score", "blur_score", "colors",
                   "estimated_size_cm", "inference_tier", "pet_identification", "candidates", "image_quality",
                   "ai_reasoning", "extracted_visual_traits"]).isSubset(of: Set(resultObject.keys)),
              let reasoning = resultObject["ai_reasoning"] as? String, !reasoning.isEmpty,
              resultObject["extracted_visual_traits"] is [String] else { throw ObservationHistoryError.invalidSnapshot }
        let payload = try JSONSerialization.data(withJSONObject: resultObject)
        let result = try JSONDecoder().decode(EdgeResponse.self, from: payload)
        guard try uuid(result.scan_id) == uuid(observationID),
              result.is_biological_subject != nil, result.is_live_capture != nil,
              let confidence = result.confidence_score, (0...1).contains(confidence),
              let blur = result.blur_score, (0...1).contains(blur),
              result.colors != nil, ["flash", "pro"].contains(result.inference_tier ?? ""),
              PrimaryIdentificationResponseValidator.isValid(result) else {
            throw ObservationHistoryError.invalidSnapshot
        }
        var photos: [ObservationHistoryPhotoReference] = []
        var audio: ObservationHistoryAudioReference?
        var video: ObservationVideoManifest?
        if version == 5 {
            let sourceID = try uuid(row["source_analysis_id"])
            guard let manifest = row["evidence_manifest"] else { throw ObservationHistoryError.invalidSnapshot }
            let decoded = try ObservationVideoManifest(data: JSONSerialization.data(withJSONObject: manifest),
                observationID: observationUUID, analysisID: analysisID)
            let graph = decoded.provenance
            let artifacts = [graph.source] + graph.frames.map(\.artifact) + (graph.audio.map { [$0.artifact] } ?? [])
            guard !artifacts.contains(where: { $0.mediaID == sourceID }) else { throw ObservationHistoryError.invalidSnapshot }
            video = decoded
        } else if version == 4 {
            audio = try ObservationHistoryAudioReference.decodeManifest(row["evidence_manifest"], observationID: observationUUID,
                analysisID: analysisID)
        } else if version == 2 {
            photos = try ObservationHistoryPhotoReference.decodeManifest(row["evidence_manifest"], observationID: observationUUID, analysisID: analysisID)
        } else {
            let evidence = try object(row["evidence_manifest"], keys: ["schema_version", "captured_media"])
            guard try integer(evidence["schema_version"]) == 1 else { throw ObservationHistoryError.invalidSnapshot }
            guard let mediaValue = evidence["captured_media"] as? [Any] else { throw ObservationHistoryError.invalidSnapshot }
            try rejectLegacyMedia(mediaValue)
            let media = try JSONDecoder().decode(CapturedMediaWireManifestDTO.self,
                from: JSONSerialization.data(withJSONObject: mediaValue))
            guard !media.items.isEmpty else { throw ObservationHistoryError.invalidSnapshot }
        }
        return Result(version: version, photos: photos, audio: audio, video: video, analysisID: analysisID,
            completedAt: Date(timeIntervalSince1970: Double(milliseconds) / 1000), importedAt: nil, bytes: bytes)
    }

    /// The generated media decoder includes legacy compatibility; new history must not.
    private static func rejectLegacyMedia(_ value: Any, depth: Int = 0) throws {
        guard depth <= 8 else { throw ObservationHistoryError.invalidSnapshot }
        if let object = value as? [String: Any] {
            guard Set(object.keys).isDisjoint(with: ["source_index", "free_text", "addedAt", "added_at"]),
                  object["storage"] as? String != "localFile",
                  !(object["video"] != nil && object["audio"] != nil) else { throw ObservationHistoryError.invalidSnapshot }
            for child in object.values { try rejectLegacyMedia(child, depth: depth + 1) }
        } else if let array = value as? [Any] {
            guard array.count <= 64 else { throw ObservationHistoryError.invalidSnapshot }
            for child in array { try rejectLegacyMedia(child, depth: depth + 1) }
        }
    }

    static func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any], Set(object.keys) == keys else { throw ObservationHistoryError.invalidPage }
        return object
    }
    static func integer(_ value: Any?, maximum: Int = 2_147_483_646) throws -> Int {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= Double(maximum),
              number.doubleValue.rounded() == number.doubleValue else { throw ObservationHistoryError.invalidPage }
        return number.intValue
    }
    static func uuid(_ value: Any?) throws -> UUID {
        guard let string = value as? String, let id = UUID(uuidString: string), id.uuidString.lowercased() == string else {
            throw ObservationHistoryError.invalidPage
        }
        return id
    }
}

/// Closed manifest-3 audio metadata, separate from photo resolution and provider execution.
struct ObservationHistoryAudioReference: Equatable, Sendable {
    let mediaID: UUID
    let contentType: String
    let byteCount: Int
    let sha256: String

    // ECMAScript String.trim used by the shared manifest decoder; Foundation's
    // whitespace set differs at U+0085 and U+FEFF. Never normalize saved text.
    private static let descriptionWhitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

    static func hasDescriptionContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: descriptionWhitespace).isEmpty
    }

    static func decodeManifest(_ value: Any?, observationID: UUID, analysisID: UUID) throws -> Self {
        let manifest = try ObservationHistoryPage.object(value, keys: ["schema_version", "items"])
        guard try ObservationHistoryPage.integer(manifest["schema_version"]) == 3,
              let items = manifest["items"] as? [[String: Any]], (1...64).contains(items.count) else {
            throw ObservationHistoryError.invalidSnapshot
        }
        var audio: Self?, textUnits = 0
        for item in items {
            if item["kind"] as? String == "description" {
                _ = try ObservationHistoryPage.object(item, keys: ["kind", "text"])
                guard let text = item["text"] as? String, hasDescriptionContent(text),
                      text.unicodeScalars.count <= 8192, text.utf16.count <= 16_384,
                      text.utf16.count <= 32_000 - textUnits else { throw ObservationHistoryError.invalidSnapshot }
                textUnits += text.utf16.count
            } else {
                _ = try ObservationHistoryPage.object(item, keys: ["kind", "media_id", "content_type", "byte_count", "sha256"])
                let mediaID = try ObservationHistoryPage.uuid(item["media_id"])
                let count = try ObservationHistoryPage.integer(item["byte_count"], maximum: 2_700_000)
                guard audio == nil, item["kind"] as? String == "audio", item["content_type"] as? String == "audio/wav",
                      mediaID != observationID, mediaID != analysisID, count >= 46,
                      let hash = item["sha256"] as? String, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                    throw ObservationHistoryError.invalidSnapshot
                }
                audio = Self(mediaID: mediaID, contentType: "audio/wav", byteCount: count, sha256: hash)
            }
        }
        guard let audio else { throw ObservationHistoryError.invalidSnapshot }
        return audio
    }
}
