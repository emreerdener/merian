import Foundation

/// Exact ordered projection of the entire submitted composition. A clip's
/// derived artifacts retain the clip's node index; notes also occupy node indexes.
struct ObservationCompositionCohortInventory: Equatable, Sendable {
    enum Role: String, Sendable {
        case image, audio
        case source = "video_source", frame = "video_frame", videoAudio = "video_audio"
    }
    struct Item: Equatable, Sendable {
        let nodeIndex: Int
        let role: Role
        let index: Int?
        let artifact: ObservationVideoProvenance.Artifact
    }
    let items: [Item]

    init(input: Data) throws {
        let request = try ObservationCompositionReanalysisRequest(savedBody: input)
        items = request.manifest.items.enumerated().flatMap { nodeIndex, node -> [Item] in
            switch node {
            case let .image(artifact): return [.init(nodeIndex: nodeIndex, role: .image, index: nil, artifact: artifact)]
            case let .audio(artifact): return [.init(nodeIndex: nodeIndex, role: .audio, index: nil, artifact: artifact)]
            case .description: return []
            case let .video(graph):
                return [.init(nodeIndex: nodeIndex, role: .source, index: nil, artifact: graph.source)]
                    + graph.frames.map { .init(nodeIndex: nodeIndex, role: .frame, index: $0.index, artifact: $0.artifact) }
                    + (graph.audio.map { [.init(nodeIndex: nodeIndex, role: .videoAudio, index: nil, artifact: $0.artifact)] } ?? [])
            }
        }
    }

    func validate(items data: Data) throws {
        guard !data.isEmpty, data.count <= 8192,
              let rows = try JSONSerialization.jsonObject(with: data) as? [Any], rows.count == items.count else {
            throw MerianError.invalidResponse
        }
        for (value, expected) in zip(rows, items) {
            let row = try ObservationHistoryPage.object(value, keys: ["node_index", "role", "frame_index", "media_id", "content_type", "byte_count", "sha256"])
            let index = row["frame_index"] is NSNull ? nil : try ObservationHistoryPage.integer(row["frame_index"])
            guard try ObservationHistoryPage.integer(row["node_index"]) == expected.nodeIndex,
                  row["role"] as? String == expected.role.rawValue, index == expected.index,
                  row["media_id"] as? String == expected.artifact.mediaID.uuidString.lowercased(),
                  row["content_type"] as? String == expected.artifact.contentType,
                  try ObservationHistoryPage.integer(row["byte_count"]) == expected.artifact.byteCount,
                  row["sha256"] as? String == expected.artifact.sha256 else { throw MerianError.invalidResponse }
        }
    }
}
