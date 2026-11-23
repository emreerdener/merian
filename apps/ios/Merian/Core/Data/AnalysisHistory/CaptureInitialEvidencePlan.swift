import Foundation

/// Client-known evidence only. Prepared audio identities reserve server output;
/// they never describe a local file or invent output bytes, sizes or hashes.
/// This value grants neither storage access nor queue/release authority.
struct CaptureInitialEvidencePlan: Equatable, Sendable {
    typealias Artifact = ObservationVideoProvenance.Artifact
    struct Audio: Equatable, Sendable {
        let source: Artifact
        let preparedMediaID: UUID
    }
    struct Video: Equatable, Sendable {
        let source: Artifact
        let playback: Artifact
        let frames: [Artifact]
        let audio: Audio?
    }
    enum Node: Equatable, Sendable {
        case image(source: Artifact, prepared: Artifact, focus: NormalizedImageFocusRegion?, preparation: ObservationInitialPhotoPreparation)
        case audio(Audio), video(Video), description(String)
    }
    enum Role: String, Sendable {
        case sourceImage = "source_image", preparedImage = "prepared_image"
        case sourceAudio = "source_audio", sourceVideo = "source_video"
        case playbackVideo = "playback_video", inferenceFrame = "inference_frame"
        case sourceCompanionAudio = "source_companion_audio"
    }
    struct Upload: Equatable, Sendable {
        let itemIndex: Int
        let role: Role
        let frameIndex: Int?
        let artifact: Artifact
    }
    let ownerID: UUID
    let scanID: UUID
    let generation: UUID
    let items: [Node]
    let uploads: [Upload]

    init(ownerID: UUID, scanID: UUID, generation: UUID, items: [Node]) throws {
        var ids: Set<UUID> = [ownerID, scanID, generation]
        guard ids.count == 3, (1...64).contains(items.count) else { throw MerianError.invalidResponse }
        var uploads: [Upload] = []
        var total = 0, imageBytes = 0, originals = 0, audioCount = 0, videos = 0, photos = 0, physical = 0, textUnits = 0
        func add(_ artifact: Artifact, role: Role, item: Int, frame: Int? = nil) throws {
            let types: Set<String>, maximum: Int
            switch role {
            case .sourceImage:
                types = ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"]; maximum = 33_554_432
            case .preparedImage, .inferenceFrame:
                types = ["image/jpeg", "image/png"]; maximum = 5_242_880
            case .sourceAudio, .sourceCompanionAudio:
                types = ["audio/wav"]; maximum = 2_700_000
            case .sourceVideo, .playbackVideo:
                types = ["video/mp4"]; maximum = 12_582_912
            }
            guard ids.insert(artifact.mediaID).inserted, types.contains(artifact.contentType),
                  (artifact.contentType == "audio/wav" ? 46 : 1)...maximum ~= artifact.byteCount,
                  artifact.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw MerianError.invalidResponse }
            total += artifact.byteCount
            if role == .sourceImage { originals += artifact.byteCount }
            if role == .preparedImage || role == .inferenceFrame { imageBytes += artifact.byteCount }
            guard total <= 72_351_744, originals <= 67_108_864, imageBytes <= 5_242_880 else { throw MerianError.invalidResponse }
            uploads.append(.init(itemIndex: item, role: role, frameIndex: frame, artifact: artifact))
        }
        func audio(_ audio: Audio, companion: Bool, item: Int) throws {
            audioCount += 1
            guard audioCount <= 2, ids.insert(audio.preparedMediaID).inserted else { throw MerianError.invalidResponse }
            try add(audio.source, role: companion ? .sourceCompanionAudio : .sourceAudio, item: item)
        }
        for (index, node) in items.enumerated() {
            switch node {
            case let .description(text):
                guard ObservationHistoryAudioReference.hasDescriptionContent(text),
                      !text.unicodeScalars.contains(where: { $0.value == 0 }), text.unicodeScalars.count <= 8192,
                      text.utf16.count <= 16_384, text.utf16.count <= 32_000 - textUnits else { throw MerianError.invalidResponse }
                textUnits += text.utf16.count
            case let .image(source, prepared, focus, preparation):
                physical += 1; photos += 1
                try add(source, role: .sourceImage, item: index)
                try add(prepared, role: .preparedImage, item: index)
                guard focus == nil || focus?.fingerprintFields != nil else { throw MerianError.invalidResponse }
                _ = try ObservationInitialPhotoPreparation(preparation.object)
            case let .audio(value):
                physical += 1
                try audio(value, companion: false, item: index)
            case let .video(video):
                physical += 1; videos += 1
                guard videos <= 1, (1...5).contains(video.frames.count) else { throw MerianError.invalidResponse }
                try add(video.source, role: .sourceVideo, item: index)
                try add(video.playback, role: .playbackVideo, item: index)
                for (frame, artifact) in video.frames.enumerated() { try add(artifact, role: .inferenceFrame, item: index, frame: frame) }
                if let value = video.audio { try audio(value, companion: true, item: index) }
            }
        }
        guard total <= 72_351_744 - audioCount * 46, physical > 0, physical <= (physical == photos ? 5 : 2) else { throw MerianError.invalidResponse }
        self.ownerID = ownerID; self.scanID = scanID; self.generation = generation
        self.items = items; self.uploads = uploads
    }

    var object: [String: Any] {
        func artifact(_ a: Artifact) -> [String: Any] {
            ["media_id": a.mediaID.uuidString.lowercased(), "content_type": a.contentType, "byte_count": a.byteCount, "sha256": a.sha256]
        }
        func audio(_ a: Audio) -> [String: Any] {
            ["source": artifact(a.source), "prepared_media_id": a.preparedMediaID.uuidString.lowercased()]
        }
        return ["schema_version": 1, "scan_id": scanID.uuidString.lowercased(), "generation": generation.uuidString.lowercased(),
            "items": items.map { node -> [String: Any] in
                switch node {
                case let .image(source, prepared, focus, preparation):
                    return ["kind": "image", "source": artifact(source), "prepared": artifact(prepared),
                        "coordinate_basis": "prepared_image_top_left_v1", "preparation": preparation.object,
                        "focus_region": focus.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height, "source": $0.source.rawValue] as [String: Any] as Any } ?? NSNull()]
                case let .description(text): return ["kind": "description", "text": text]
                case let .audio(value): return audio(value).merging(["kind": "audio"]) { _, new in new }
                case let .video(video): return ["kind": "video", "source": artifact(video.source), "playback": artifact(video.playback),
                    "frames": video.frames.map(artifact), "audio": video.audio.map { audio($0) as Any } ?? NSNull()]
                }
            }]
    }

    func encoded() throws -> Data {
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= 1_044_736 else { throw MerianError.invalidResponse }
        return bytes
    }

    init(ownerID: UUID, data: Data) throws {
        guard data.count <= 1_044_736 else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: ["schema_version", "scan_id", "generation", "items"])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 1, let values = row["items"] as? [Any], (1...64).contains(values.count) else { throw MerianError.invalidResponse }
        func artifact(_ value: Any?) throws -> Artifact {
            let item = try ObservationHistoryPage.object(value, keys: ["media_id", "content_type", "byte_count", "sha256"])
            guard let type = item["content_type"] as? String, let hash = item["sha256"] as? String else { throw MerianError.invalidResponse }
            return try .init(mediaID: ObservationHistoryPage.uuid(item["media_id"]), contentType: type,
                             byteCount: ObservationHistoryPage.integer(item["byte_count"], maximum: 33_554_432), sha256: hash)
        }
        func audio(_ value: Any?) throws -> Audio {
            let row = try ObservationHistoryPage.object(value, keys: ["source", "prepared_media_id"])
            return try .init(source: artifact(row["source"]), preparedMediaID: ObservationHistoryPage.uuid(row["prepared_media_id"]))
        }
        let nodes: [Node] = try values.map { value in
            guard let raw = value as? [String: Any], let kind = raw["kind"] as? String else { throw MerianError.invalidResponse }
            switch kind {
            case "description":
                let node = try ObservationHistoryPage.object(raw, keys: ["kind", "text"])
                guard let text = node["text"] as? String else { throw MerianError.invalidResponse }; return .description(text)
            case "image":
                let node = try ObservationHistoryPage.object(raw, keys: ["kind", "source", "prepared", "coordinate_basis", "focus_region", "preparation"])
                guard node["coordinate_basis"] as? String == "prepared_image_top_left_v1" else { throw MerianError.invalidResponse }
                let focus: NormalizedImageFocusRegion?
                if node["focus_region"] is NSNull { focus = nil } else {
                    let region = try ObservationHistoryPage.object(node["focus_region"], keys: ["x", "y", "width", "height", "source"])
                    focus = try JSONDecoder().decode(NormalizedImageFocusRegion.self, from: JSONSerialization.data(withJSONObject: region))
                }
                return try .image(source: artifact(node["source"]), prepared: artifact(node["prepared"]), focus: focus,
                                  preparation: ObservationInitialPhotoPreparation(node["preparation"]))
            case "audio":
                let node = try ObservationHistoryPage.object(raw, keys: ["kind", "source", "prepared_media_id"])
                return try .audio(audio(["source": node["source"]!, "prepared_media_id": node["prepared_media_id"]!]))
            case "video":
                let node = try ObservationHistoryPage.object(raw, keys: ["kind", "source", "playback", "frames", "audio"])
                guard let frames = node["frames"] as? [Any], (1...5).contains(frames.count) else { throw MerianError.invalidResponse }
                return try .video(.init(source: artifact(node["source"]), playback: artifact(node["playback"]),
                                       frames: frames.map(artifact), audio: node["audio"] is NSNull ? nil : audio(node["audio"])))
            default: throw MerianError.invalidResponse
            }
        }
        try self.init(ownerID: ownerID, scanID: ObservationHistoryPage.uuid(row["scan_id"]),
                      generation: ObservationHistoryPage.uuid(row["generation"]), items: nodes)
    }
}
