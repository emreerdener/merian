import CryptoKit
import Foundation

/// Exact, validated preparation bytes. Video is accepted only from the existing
/// retained-clip cohort; arbitrary arrays cannot manufacture that provenance.
struct ObservationCompositionPayload: Sendable {
    let request: ObservationCompositionReanalysisRequest
    let bytes: [Data]
    private init(request: ObservationCompositionReanalysisRequest, bytes: [Data]) {
        self.request = request; self.bytes = bytes
    }

    static func prepare(request: ObservationCompositionReanalysisRequest, standalone: [UUID: Data],
                        video: ObservationVideoCohort.Payload? = nil) throws -> Self {
        var bytes: [Data] = [], consumed = Set<UUID>(), usedVideo = false
        for node in request.manifest.items {
            switch node {
            case let .image(artifact), let .audio(artifact):
                guard let data = standalone[artifact.mediaID], consumed.insert(artifact.mediaID).inserted else {
                    throw MerianError.invalidResponse
                }
                try validateStandalone(data, artifact: artifact)
                bytes.append(data)
            case let .video(graph):
                guard !usedVideo, let video, video.request.observationID == request.observationID,
                      video.request.analysisID == request.analysisID, video.request.sourceAnalysisID == request.sourceAnalysisID,
                      video.request.manifest.provenance == graph else { throw MerianError.invalidResponse }
                usedVideo = true
                bytes.append(contentsOf: video.bytes)
            case .description: break
            }
        }
        guard consumed == Set(standalone.keys), usedVideo == (video != nil) else { throw MerianError.invalidResponse }
        return Self(request: request, bytes: bytes)
    }

    static func validateStandalone(_ bytes: Data, artifact: ObservationCompositionManifest.Artifact) throws {
        if artifact.contentType == "audio/wav" {
            guard ObservationAudioContainer.isValid(bytes), bytes.count == artifact.byteCount,
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == artifact.sha256 else { throw MerianError.invalidResponse }
        } else {
            _ = try ObservationReanalysisPhotoPreparation.prepare(bytes: bytes, mediaID: artifact.mediaID,
                original: .init(mediaID: artifact.mediaID, contentType: artifact.contentType,
                    byteCount: artifact.byteCount, sha256: artifact.sha256))
        }
    }
}
