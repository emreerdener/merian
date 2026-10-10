import CoreFoundation
import Foundation

/// Private metadata only; validation does not prove bytes, ownership, or provider readiness.
struct ObservationVideoProvenance: Equatable, Sendable {
    struct Artifact: Equatable, Sendable {
        let mediaID: UUID
        let contentType: String
        let byteCount: Int
        let sha256: String
    }
    struct Parameters: Equatable, Sendable {
        let durationTicks: Int
        let cropCenterBasisPoints: Int
        let inferenceLongEdge: Int
        // All other parameters are fixed by retained_clip_v1/direct_inference_v1.
    }
    struct Frame: Equatable, Sendable {
        let index: Int
        let sourceMediaID: UUID
        let requestedTimeTicks: Int
        let actualTimeTicks: Int
        let artifact: Artifact
    }
    struct Audio: Equatable, Sendable {
        let sourceMediaID: UUID
        let startTicks: Int
        let endTicks: Int
        let sampleCount: Int
        let artifact: Artifact
    }
    let source: Artifact
    let parameters: Parameters
    let frames: [Frame]
    let audio: Audio?

    private init(source: Artifact, parameters: Parameters, frames: [Frame], audio: Audio?) {
        self.source = source; self.parameters = parameters; self.frames = frames; self.audio = audio
    }

    static func decode(_ value: Any?, observationID: UUID, analysisID: UUID) throws -> Self {
        guard observationID != analysisID else { throw ObservationHistoryError.invalidSnapshot }
        var seen: Set<UUID> = [observationID, analysisID]
        let row = try ObservationHistoryPage.object(value, keys: ["schema_version", "preprocessing_version", "source", "parameters", "frames", "audio"])
        guard try number(row["schema_version"], 1...1) == 1,
              row["preprocessing_version"] as? String == "retained_clip_v1" else { throw ObservationHistoryError.invalidSnapshot }
        func artifact(_ value: Any?, types: Set<String>, bytes: ClosedRange<Int>) throws -> Artifact {
            let item = try ObservationHistoryPage.object(value, keys: ["media_id", "content_type", "byte_count", "sha256"])
            let id = try ObservationHistoryPage.uuid(item["media_id"])
            guard seen.insert(id).inserted, let type = item["content_type"] as? String, types.contains(type),
                  let hash = item["sha256"] as? String, hash.utf8.count == 64,
                  hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw ObservationHistoryError.invalidSnapshot }
            return Artifact(mediaID: id, contentType: type, byteCount: try number(item["byte_count"], bytes), sha256: hash)
        }
        let source = try artifact(row["source"], types: ["video/mp4"], bytes: 1...12_582_912)
        let p = try ObservationHistoryPage.object(row["parameters"], keys: ["timescale", "frame_pipeline", "decode_long_edge", "duration_ticks", "sampling", "preferred_track_transform", "crop", "crop_center_basis_points", "inference_long_edge", "encoding_quality_percent"])
        guard try number(p["timescale"], 600...600) == 600,
              try number(p["decode_long_edge"], 2048...2048) == 2048,
              try number(p["encoding_quality_percent"], 85...85) == 85,
              p["frame_pipeline"] as? String == "direct_inference_v1", p["sampling"] as? String == "five_interior_v1",
              p["crop"] as? String == "square_v1", let transform = p["preferred_track_transform"] as? NSNumber,
              CFGetTypeID(transform) == CFBooleanGetTypeID(), transform.boolValue else { throw ObservationHistoryError.invalidSnapshot }
        let duration = try number(p["duration_ticks"], 60...3000)
        let edge = try number(p["inference_long_edge"], 768...1024)
        guard edge == 768 || edge == 1024, let inputs = row["frames"] as? [Any], inputs.count == 5 else { throw ObservationHistoryError.invalidSnapshot }
        let parameters = Parameters(durationTicks: duration, cropCenterBasisPoints: try number(p["crop_center_basis_points"], 0...10000), inferenceLongEdge: edge)
        var frameBytes = 0
        var previousTime = 0
        let frames = try inputs.enumerated().map { index, value in
            let frame = try ObservationHistoryPage.object(value, keys: ["index", "source_media_id", "requested_time_ticks", "actual_time_ticks", "artifact"])
            let expected = min(max((duration * (1 + 2 * index) + 5) / 10, 30), duration - 30)
            guard try number(frame["index"], index...index) == index,
                  try ObservationHistoryPage.uuid(frame["source_media_id"]) == source.mediaID,
                  try number(frame["requested_time_ticks"], expected...expected) == expected else { throw ObservationHistoryError.invalidSnapshot }
            let output = try artifact(frame["artifact"], types: ["image/webp", "image/jpeg"], bytes: 1...5_242_880)
            frameBytes += output.byteCount
            guard frameBytes <= 5_242_880 else { throw ObservationHistoryError.invalidSnapshot }
            let actual = try number(frame["actual_time_ticks"], previousTime...(duration - 1))
            previousTime = actual
            return Frame(index: index, sourceMediaID: source.mediaID, requestedTimeTicks: expected, actualTimeTicks: actual, artifact: output)
        }
        let audio: Audio?
        if row["audio"] is NSNull {
            audio = nil
        } else {
            let item = try ObservationHistoryPage.object(row["audio"], keys: ["source_media_id", "track", "start_ticks", "end_ticks", "sample_rate", "sample_count", "channels", "bits_per_sample", "encoding", "artifact"])
            guard try ObservationHistoryPage.uuid(item["source_media_id"]) == source.mediaID,
                  item["track"] as? String == "first_audio_track", item["encoding"] as? String == "pcm_s16le",
                  try number(item["sample_rate"], 44100...44100) == 44100,
                  try number(item["channels"], 1...1) == 1,
                  try number(item["bits_per_sample"], 16...16) == 16 else { throw ObservationHistoryError.invalidSnapshot }
            let start = try number(item["start_ticks"], 0...(duration - 1))
            let end = try number(item["end_ticks"], (start + 1)...duration)
            let samples = try number(item["sample_count"], 1...220500)
            guard abs(samples * 600 - (end - start) * 44100) <= 44100 else { throw ObservationHistoryError.invalidSnapshot }
            audio = Audio(sourceMediaID: source.mediaID, startTicks: start, endTicks: end, sampleCount: samples,
                          artifact: try artifact(item["artifact"], types: ["audio/wav"], bytes: (44 + samples * 2)...2_700_000))
        }
        return Self(source: source, parameters: parameters, frames: frames, audio: audio)
    }

    static func number(_ value: Any?, _ range: ClosedRange<Int>) throws -> Int {
        let value = try ObservationHistoryPage.integer(value, maximum: range.upperBound)
        guard range.contains(value) else { throw ObservationHistoryError.invalidSnapshot }
        return value
    }
}
