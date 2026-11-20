import CryptoKit
import Foundation

/// Held V4 metadata identity. No saved-request restoration, ownership or admission authority.
/// Separate from the installed photo/audio codec; SQL parity is required before use.
struct ObservationVideoSourceFingerprint: Equatable, Sendable {
    let canonicalBytes: Data
    let sha256: String

    init(input: Data) throws {
        guard !input.isEmpty, input.count <= 1_044_480 else { throw MerianError.invalidResponse }
        let row = try ObservationHistoryPage.object(JSONSerialization.jsonObject(with: input), keys: [
            "schema_version", "observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest",
            "entitlement_protocol", "identification_protocol", "history_protocol", "expected_processor_permission"
        ])
        guard try ObservationHistoryPage.integer(row["schema_version"]) == 4,
              try ObservationHistoryPage.integer(row["entitlement_protocol"]) == 3,
              try ObservationHistoryPage.integer(row["identification_protocol"]) == 6,
              try ObservationHistoryPage.integer(row["history_protocol"]) == 9,
              row["expected_processor_permission"] as? String == "google_gemini",
              let digest = row["request_digest"] as? String, digest.utf8.count == 64,
              digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw MerianError.invalidResponse }
        let observation = try ObservationHistoryPage.uuid(row["observation_id"])
        let analysis = try ObservationHistoryPage.uuid(row["analysis_id"])
        let source = try ObservationHistoryPage.uuid(row["source_analysis_id"])
        guard Set([observation, analysis, source]).count == 3 else { throw MerianError.invalidResponse }
        let manifestRow = try ObservationHistoryPage.object(row["evidence_manifest"], keys: ["schema_version", "provenance", "descriptions"])
        let manifest = try ObservationVideoManifest(data: JSONSerialization.data(withJSONObject: manifestRow),
                                                   observationID: observation, analysisID: analysis)
        let graph = manifest.provenance
        let artifacts = [graph.source] + graph.frames.map(\.artifact) + (graph.audio.map { [$0.artifact] } ?? [])
        guard !artifacts.contains(where: { $0.mediaID == source }) else { throw MerianError.invalidResponse }
        var fields = ["merian.analysis-video-source-binding", "1", "4", observation.uuidString.lowercased(),
                      analysis.uuidString.lowercased(), source.uuidString.lowercased(), digest, "3", "6", "9", "google_gemini",
                      graph.audio == nil ? "multimodal_video_frames_v1" : "multimodal_video_audio_v1", "4", "1", "retained_clip_v1"]
        func appendArtifact(_ artifact: ObservationVideoProvenance.Artifact) {
            fields += [artifact.mediaID.uuidString.lowercased(), artifact.contentType, String(artifact.byteCount), artifact.sha256]
        }
        appendArtifact(graph.source)
        let p = graph.parameters
        fields += ["600", "direct_inference_v1", "2048", String(p.durationTicks), "five_interior_v1", "1", "square_v1",
                   String(p.cropCenterBasisPoints), String(p.inferenceLongEdge), "85", String(graph.frames.count)]
        for frame in graph.frames {
            fields += [String(frame.index), frame.sourceMediaID.uuidString.lowercased(), String(frame.requestedTimeTicks), String(frame.actualTimeTicks)]
            appendArtifact(frame.artifact)
        }
        fields.append(graph.audio == nil ? "0" : "1")
        if let audio = graph.audio {
            fields += [audio.sourceMediaID.uuidString.lowercased(), "first_audio_track", String(audio.startTicks), String(audio.endTicks),
                       "44100", String(audio.sampleCount), "1", "16", "pcm_s16le"]
            appendArtifact(audio.artifact)
        }
        fields += [String(manifest.descriptions.count)] + manifest.descriptions
        var bytes = Data()
        for field in fields {
            guard !field.unicodeScalars.contains(where: { $0.value == 0 }) else { throw MerianError.invalidResponse }
            let value = Data(field.utf8), prefix = Data("\(field.utf8.count):".utf8)
            guard prefix.count + value.count + 1 <= 262_144 - bytes.count else { throw MerianError.invalidResponse }
            bytes.append(prefix); bytes.append(value); bytes.append(0x2c)
        }
        canonicalBytes = bytes
        sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

}
