import CryptoKit
import Foundation

/// Original ordinary submission evidence. A retained video does not claim a
/// reanalysis sampling/crop recipe that the original capture never recorded.
struct ObservationInitialEvidence: Equatable, Sendable {
    typealias Artifact = ObservationVideoProvenance.Artifact
    struct Audio: Equatable, Sendable { let source: Artifact; let prepared: Artifact }
    struct Video: Equatable, Sendable {
        let source: Artifact
        let playback: Artifact
        let frames: [Artifact]
        let audio: Audio?
    }
    enum Node: Equatable, Sendable {
        case image(source: Artifact, prepared: Artifact, focus: NormalizedImageFocusRegion?)
        case audio(Audio), video(Video), description(String)
    }
    let ownerID: UUID
    let generation: UUID
    let digest: String
    let manifestVersion: Int
    let items: [Node]
    /// Source geometry is keyed by the digest-bound prepared artifact identity.
    let photoPreparations: [UUID: ObservationInitialPhotoPreparation]

    var artifacts: [Artifact] {
        items.flatMap { item in
            switch item {
            case let .image(source, prepared, _): return [source, prepared]
            case let .audio(audio): return [audio.source, audio.prepared]
            case let .video(video):
                return [video.source, video.playback] + video.frames
                    + (video.audio.map { [$0.source, $0.prepared] } ?? [])
            case .description: return []
            }
        }
    }

    init(manifest: Any?, proof: Any?, observationID: UUID, analysisID: UUID, requestDigest: String) throws {
        let proof = try ObservationHistoryPage.object(proof, keys: ["schema_version", "owner_id", "scan_id", "generation", "evidence_digest"])
        ownerID = try ObservationHistoryPage.uuid(proof["owner_id"])
        generation = try ObservationHistoryPage.uuid(proof["generation"])
        var seen: Set<UUID> = [ownerID, generation, observationID, analysisID]
        guard seen.count == 4, try ObservationHistoryPage.integer(proof["schema_version"]) == 1,
              try ObservationHistoryPage.uuid(proof["scan_id"]) == observationID,
              proof["evidence_digest"] as? String == requestDigest else { throw ObservationHistoryError.invalidSnapshot }
        let row = try ObservationHistoryPage.object(manifest, keys: ["schema_version", "items"])
        let version = try ObservationHistoryPage.integer(row["schema_version"])
        guard [7, 8, 9].contains(version),
              let values = row["items"] as? [Any], (1...64).contains(values.count) else { throw ObservationHistoryError.invalidSnapshot }
        manifestVersion = version
        var fields = ["merian.initial-evidence", "1", observationID.uuidString.lowercased(), generation.uuidString.lowercased(), String(version), String(values.count)]
        var total = 0, imageBytes = 0, originalBytes = 0, audioCount = 0, videoCount = 0, photos = 0, physical = 0, textUnits = 0
        func artifact(_ value: Any?, kind: String, source: Bool = false) throws -> Artifact {
            let item = try ObservationHistoryPage.object(value, keys: ["media_id", "content_type", "byte_count", "sha256"])
            let id = try ObservationHistoryPage.uuid(item["media_id"])
            let types: [String]
            switch kind {
            case "image": types = source ? ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"] : ["image/jpeg", "image/png"]
            case "audio": types = source ? ["audio/wav", "audio/mp4"] : ["audio/wav"]
            default: types = ["video/mp4"]
            }
            guard seen.insert(id).inserted, let type = item["content_type"] as? String, types.contains(type),
                  let hash = item["sha256"] as? String, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw ObservationHistoryError.invalidSnapshot
            }
            let max = kind == "video" ? 12_582_912 : kind == "audio" ? 2_700_000
                : (source && version >= 8 ? 33_554_432 : 5_242_880)
            let count = try ObservationVideoProvenance.number(item["byte_count"], (type == "audio/wav" ? 46 : 1)...max)
            total += count
            if kind == "image", !source { imageBytes += count }
            if kind == "image", source { originalBytes += count }
            guard total <= (version >= 8 ? 72_351_744 : 33_554_432), imageBytes <= 5_242_880,
                  version < 8 || originalBytes <= 67_108_864 else { throw ObservationHistoryError.invalidSnapshot }
            fields += [id.uuidString.lowercased(), type, String(count), hash]
            return Artifact(mediaID: id, contentType: type, byteCount: count, sha256: hash)
        }
        func audio(_ value: Any?) throws -> Audio {
            audioCount += 1
            guard audioCount <= 2 else { throw ObservationHistoryError.invalidSnapshot }
            let item = try ObservationHistoryPage.object(value, keys: ["source", "prepared"])
            return try Audio(source: artifact(item["source"], kind: "audio", source: true), prepared: artifact(item["prepared"], kind: "audio"))
        }
        var preparations: [UUID: ObservationInitialPhotoPreparation] = [:]
        items = try values.map { value in
            guard let raw = value as? [String: Any], let kind = raw["kind"] as? String else { throw ObservationHistoryError.invalidSnapshot }
            fields.append(kind)
            if kind == "description" {
                let item = try ObservationHistoryPage.object(raw, keys: ["kind", "text"])
                guard let text = item["text"] as? String, ObservationHistoryAudioReference.hasDescriptionContent(text),
                      !text.unicodeScalars.contains(where: { $0.value == 0 }), text.unicodeScalars.count <= 8192,
                      text.utf16.count <= 16_384, text.utf16.count <= 32_000 - textUnits else { throw ObservationHistoryError.invalidSnapshot }
                textUnits += text.utf16.count; fields.append(text)
                return .description(text)
            }
            physical += 1
            switch kind {
            case "image":
                photos += 1
                let keys: Set<String> = ["kind", "source", "prepared", "coordinate_basis", "focus_region"]
                let item = try ObservationHistoryPage.object(raw, keys: version == 9 ? keys.union(["preparation"]) : keys)
                guard item["coordinate_basis"] as? String == "prepared_image_top_left_v1" else { throw ObservationHistoryError.invalidSnapshot }
                let source = try artifact(item["source"], kind: "image", source: true)
                let prepared = try artifact(item["prepared"], kind: "image")
                fields += ["prepared_image_top_left_v1", item["focus_region"] is NSNull ? "0" : "1"]
                var focus: NormalizedImageFocusRegion?
                if !(item["focus_region"] is NSNull) {
                    let region = try ObservationHistoryPage.object(item["focus_region"], keys: ["x", "y", "width", "height", "source"])
                    let decoded = try JSONDecoder().decode(NormalizedImageFocusRegion.self, from: JSONSerialization.data(withJSONObject: region))
                    guard let encoded = decoded.fingerprintFields else { throw ObservationHistoryError.invalidSnapshot }
                    fields += encoded; focus = decoded
                }
                if version == 9 {
                    let preparation = try ObservationInitialPhotoPreparation(item["preparation"])
                    fields += preparation.fingerprintFields
                    preparations[prepared.mediaID] = preparation
                }
                return .image(source: source, prepared: prepared, focus: focus)
            case "audio":
                let item = try ObservationHistoryPage.object(raw, keys: ["kind", "source", "prepared"])
                return try .audio(audio(["source": item["source"]!, "prepared": item["prepared"]!]))
            case "video":
                videoCount += 1
                let item = try ObservationHistoryPage.object(raw, keys: ["kind", "source", "playback", "frames", "audio"])
                guard videoCount <= 1, let frames = item["frames"] as? [Any], (1...5).contains(frames.count) else {
                    throw ObservationHistoryError.invalidSnapshot
                }
                let source = try artifact(item["source"], kind: "video", source: true)
                let playback = try artifact(item["playback"], kind: "video")
                fields.append(String(frames.count))
                let decodedFrames = try frames.map { try artifact($0, kind: "image") }
                fields.append(item["audio"] is NSNull ? "0" : "1")
                let sound = item["audio"] is NSNull ? nil : try audio(item["audio"])
                return .video(Video(source: source, playback: playback, frames: decodedFrames, audio: sound))
            default: throw ObservationHistoryError.invalidSnapshot
            }
        }
        guard physical > 0, physical <= (physical == photos ? 5 : 2) else { throw ObservationHistoryError.invalidSnapshot }
        let bytes = Data(fields.map { "\($0.utf8.count):\($0)," }.joined().utf8)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard hash == requestDigest else { throw ObservationHistoryError.invalidSnapshot }
        photoPreparations = preparations
        digest = hash
    }
}
