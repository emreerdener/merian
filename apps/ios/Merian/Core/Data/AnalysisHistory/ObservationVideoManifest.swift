import Foundation

/// Bounded private manifest codec. Decoding preserves original bytes; construction round-trips the same closed schema.
struct ObservationVideoManifest: Equatable, Sendable {
    let provenance: ObservationVideoProvenance
    let descriptions: [String]
    let originalBytes: Data

    init(data: Data, observationID: UUID, analysisID: UUID) throws {
        guard !data.isEmpty, data.count <= 1_044_480 else { throw ObservationHistoryError.invalidSnapshot }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: data), keys: ["schema_version", "provenance", "descriptions"])
        guard try ObservationVideoProvenance.number(row["schema_version"], 4...4) == 4,
              let texts = row["descriptions"] as? [String], texts.count <= 64 else { throw ObservationHistoryError.invalidSnapshot }
        try Self.validateDescriptions(texts)
        provenance = try ObservationVideoProvenance.decode(row["provenance"], observationID: observationID, analysisID: analysisID)
        descriptions = texts
        originalBytes = data
    }

    static func validateDescriptions(_ texts: [String]) throws {
        guard texts.count <= 64 else { throw ObservationHistoryError.invalidSnapshot }
        var units = 0
        for text in texts {
            let count = text.utf16.prefix(16385).count
            guard count <= 16384, text.unicodeScalars.prefix(8193).count <= 8192,
                  count <= 32000 - units, ObservationHistoryAudioReference.hasDescriptionContent(text) else {
                throw ObservationHistoryError.invalidSnapshot
            }
            units += count
        }
    }

    static func prepared(source: ObservationVideoProvenance.Artifact, parameters: ObservationVideoProvenance.Parameters,
                         frames: [ObservationVideoProvenance.Frame], audio: ObservationVideoProvenance.Audio?,
                         descriptions: [String], observationID: UUID, analysisID: UUID) throws -> Self {
        try validateDescriptions(descriptions)
        guard frames.count == 5 else { throw ObservationHistoryError.invalidSnapshot }
        func artifact(_ item: ObservationVideoProvenance.Artifact) -> [String: Any] {
            ["media_id": item.mediaID.uuidString.lowercased(), "content_type": item.contentType,
             "byte_count": item.byteCount, "sha256": item.sha256]
        }
        let sound: Any
        if let audio {
            sound = ["source_media_id": audio.sourceMediaID.uuidString.lowercased(), "track": "first_audio_track",
                     "start_ticks": audio.startTicks, "end_ticks": audio.endTicks, "sample_rate": 44100,
                     "sample_count": audio.sampleCount, "channels": 1, "bits_per_sample": 16, "encoding": "pcm_s16le",
                     "artifact": artifact(audio.artifact)] as [String: Any]
        } else { sound = NSNull() }
        let provenance: [String: Any] = [
            "schema_version": 1, "preprocessing_version": "retained_clip_v1", "source": artifact(source),
            "parameters": ["timescale": 600, "frame_pipeline": "direct_inference_v1", "decode_long_edge": 2048,
                           "duration_ticks": parameters.durationTicks, "sampling": "five_interior_v1",
                           "preferred_track_transform": true, "crop": "square_v1", "crop_center_basis_points": parameters.cropCenterBasisPoints,
                           "inference_long_edge": parameters.inferenceLongEdge, "encoding_quality_percent": 85] as [String: Any],
            "frames": frames.map { ["index": $0.index, "source_media_id": $0.sourceMediaID.uuidString.lowercased(),
                                    "requested_time_ticks": $0.requestedTimeTicks, "actual_time_ticks": $0.actualTimeTicks,
                                    "artifact": artifact($0.artifact)] as [String: Any] }, "audio": sound
        ]
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 4, "provenance": provenance, "descriptions": descriptions],
                                               options: [.sortedKeys, .withoutEscapingSlashes])
        return try Self(data: data, observationID: observationID, analysisID: analysisID)
    }

}
