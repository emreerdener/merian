import Foundation

/// Ordered private metadata for one child. This is not a media-byte, account,
/// upload or execution capability. Existing manifest generations remain intact.
struct ObservationCompositionManifest: Equatable, Sendable {
    typealias Artifact = ObservationVideoProvenance.Artifact
    enum Node: Equatable, Sendable {
        case image(Artifact), audio(Artifact), video(ObservationVideoProvenance), description(String)
    }
    let items: [Node]
    let schemaVersion: Int
    let imageFocusRegions: [UUID: NormalizedImageFocusRegion]
    let originalBytes: Data

    init(data: Data, observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID) throws {
        guard !data.isEmpty, data.count <= 1_044_480 else { throw ObservationHistoryError.invalidSnapshot }
        var seen: Set<UUID> = [observationID, analysisID, sourceAnalysisID]
        guard seen.count == 3 else { throw ObservationHistoryError.invalidSnapshot }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: ["schema_version", "items"])
        let version = try ObservationHistoryPage.integer(row["schema_version"])
        guard [5, 6].contains(version),
              let values = row["items"] as? [Any], (1...64).contains(values.count) else {
            throw ObservationHistoryError.invalidSnapshot
        }
        var physical = 0, photos = 0, audio = 0, videos = 0, textUnits = 0
        var imageBytes = 0, totalBytes = 0
        var focusRegions: [UUID: NormalizedImageFocusRegion] = [:]
        func retain(_ artifact: Artifact) throws {
            guard seen.insert(artifact.mediaID).inserted else { throw ObservationHistoryError.invalidSnapshot }
            totalBytes += artifact.byteCount
            if artifact.contentType.hasPrefix("image/") { imageBytes += artifact.byteCount }
            if artifact.contentType == "audio/wav" { audio += 1 }
            guard totalBytes <= 33_554_432, imageBytes <= 5_242_880, audio <= 2 else {
                throw ObservationHistoryError.invalidSnapshot
            }
        }
        items = try values.map { value in
            guard let raw = value as? [String: Any], let kind = raw["kind"] as? String else {
                throw ObservationHistoryError.invalidSnapshot
            }
            if kind == "description" {
                let item = try ObservationHistoryPage.object(raw, keys: ["kind", "text"])
                guard let text = item["text"] as? String,
                      text.utf16.count <= 16_384, text.unicodeScalars.count <= 8_192,
                      text.utf16.count <= 32_000 - textUnits,
                      !text.unicodeScalars.contains(where: { $0.value == 0 }),
                      ObservationHistoryAudioReference.hasDescriptionContent(text) else {
                    throw ObservationHistoryError.invalidSnapshot
                }
                textUnits += text.utf16.count
                return .description(text)
            }
            physical += 1
            if kind == "video" {
                videos += 1
                guard videos <= 1 else { throw ObservationHistoryError.invalidSnapshot }
                let item = try ObservationHistoryPage.object(raw, keys: ["kind", "provenance"])
                let graph = try ObservationVideoProvenance.decode(item["provenance"], observationID: observationID, analysisID: analysisID)
                try retain(graph.source)
                for frame in graph.frames { try retain(frame.artifact) }
                if let sound = graph.audio { try retain(sound.artifact) }
                return .video(graph)
            }
            guard kind == "image" || kind == "audio" else { throw ObservationHistoryError.invalidSnapshot }
            let hasFocus = version == 6 && kind == "image" && raw.keys.contains("focus_region")
            let item = try ObservationHistoryPage.object(raw, keys: hasFocus ? ["kind", "artifact", "focus_region"] : ["kind", "artifact"])
            let encoded = try ObservationHistoryPage.object(item["artifact"], keys: ["media_id", "content_type", "byte_count", "sha256"])
            let image = kind == "image"
            guard let contentType = encoded["content_type"] as? String,
                  (image ? ["image/jpeg", "image/png"] : ["audio/wav"]).contains(contentType),
                  let hash = encoded["sha256"] as? String, hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ObservationHistoryError.invalidSnapshot
            }
            let artifact = Artifact(mediaID: try ObservationHistoryPage.uuid(encoded["media_id"]), contentType: contentType,
                byteCount: try ObservationVideoProvenance.number(encoded["byte_count"], image ? 1...5_242_880 : 46...2_700_000), sha256: hash)
            try retain(artifact)
            if image { photos += 1 }
            if hasFocus {
                let region = try ObservationHistoryPage.object(item["focus_region"], keys: ["x", "y", "width", "height", "source"])
                let focus = try JSONDecoder().decode(NormalizedImageFocusRegion.self, from: JSONSerialization.data(withJSONObject: region))
                guard focus.isValidEvidence else { throw ObservationHistoryError.invalidSnapshot }
                focusRegions[artifact.mediaID] = focus
            }
            return image ? .image(artifact) : .audio(artifact)
        }
        guard physical > 0, physical <= (physical == photos ? 5 : 2) else { throw ObservationHistoryError.invalidSnapshot }
        originalBytes = data
        schemaVersion = version
        imageFocusRegions = focusRegions
    }
}
