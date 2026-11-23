import CryptoKit
import Foundation

extension ObservationCompositionReanalysisRequest {
    /// Cross-runtime UTF-8 netstrings; never normalize notes or rewrite saved bodies.
    func sourceFingerprint() throws -> String {
        let bytes = try Self.canonicalCompositionBytes(observationID: observationID, analysisID: analysisID,
            sourceAnalysisID: sourceAnalysisID, requestDigest: requestDigest, manifest: manifest)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// V5 source bytes are unchanged. V6 unsigned request and source binding
    /// share typed fields, avoiding JSON decimal formatting in either digest.
    static func canonicalCompositionBytes(observationID: UUID, analysisID: UUID, sourceAnalysisID: UUID,
                                          requestDigest: String?, manifest: ObservationCompositionManifest) throws -> Data {
        let focused = manifest.schemaVersion == 6
        guard requestDigest != nil || focused else { throw ObservationHistoryError.invalidSnapshot }
        var fields = [requestDigest == nil ? "merian.analysis-composition-request" : "merian.analysis-composition-source-binding",
            focused ? "2" : "1", String(manifest.schemaVersion), observationID.uuidString.lowercased(),
            analysisID.uuidString.lowercased(), sourceAnalysisID.uuidString.lowercased()]
        if let requestDigest { fields.append(requestDigest) }
        fields += ["3", "7", "10", "google_gemini", String(manifest.schemaVersion), String(manifest.items.count)]
        func artifact(_ value: ObservationVideoProvenance.Artifact) {
            fields += [value.mediaID.uuidString.lowercased(), value.contentType, String(value.byteCount), value.sha256]
        }
        for item in manifest.items {
            switch item {
            case let .description(text): fields += ["description", text]
            case let .image(value):
                fields.append("image"); artifact(value)
                if focused {
                    let focus = manifest.imageFocusRegions[value.mediaID]
                    fields.append(focus == nil ? "0" : "1")
                    if let focus {
                        guard let encoded = focus.fingerprintFields else { throw ObservationHistoryError.invalidSnapshot }
                        fields += encoded
                    }
                }
            case let .audio(value): fields.append("audio"); artifact(value)
            case let .video(graph):
                fields += ["video", "1", "retained_clip_v1"]
                artifact(graph.source)
                let p = graph.parameters
                fields += ["600", "direct_inference_v1", "2048", String(p.durationTicks), "five_interior_v1", "1", "square_v1",
                    String(p.cropCenterBasisPoints), String(p.inferenceLongEdge), "85", String(graph.frames.count)]
                for frame in graph.frames {
                    fields += [String(frame.index), frame.sourceMediaID.uuidString.lowercased(),
                        String(frame.requestedTimeTicks), String(frame.actualTimeTicks)]
                    artifact(frame.artifact)
                }
                fields.append(graph.audio == nil ? "0" : "1")
                if let audio = graph.audio {
                    fields += [audio.sourceMediaID.uuidString.lowercased(), "first_audio_track", String(audio.startTicks),
                        String(audio.endTicks), "44100", String(audio.sampleCount), "1", "16", "pcm_s16le"]
                    artifact(audio.artifact)
                }
            }
        }
        var bytes = Data()
        for field in fields {
            guard !field.unicodeScalars.contains(where: { $0.value == 0 }) else { throw ObservationHistoryError.invalidSnapshot }
            bytes.append(Data("\(field.utf8.count):\(field),".utf8))
            guard bytes.count <= 262_144 else { throw ObservationHistoryError.invalidSnapshot }
        }
        return bytes
    }
}
