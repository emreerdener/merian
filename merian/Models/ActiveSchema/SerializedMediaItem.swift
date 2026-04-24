import Foundation

/// A serializable representation of captured media elements, preserving chronological order
/// across image, audio, and textual modalities for persistent storage.
enum SerializedMediaItem: Codable, Equatable {
    case image(String)
    case audio(String)
    case description(ObservationContext)
}

/// Canonical decoder for persisted media JSON shared by live and historic scan flows.
enum MediaJSONParser {
    static func parse(jsonString: String) -> ActiveScanMedia? {
        guard let jsonData = jsonString.data(using: .utf8),
              let serializedItems = try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData) else {
            return nil
        }

        var items: [MediaItem] = []
        for serialized in serializedItems {
            switch serialized {
            case .image(let path):
                items.append(.image(path))
            case .audio(let path):
                let docsPath = URL.documentsDirectory.appendingPathComponent(path).path
                let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(path).path
                let resolvedPath = FileManager.default.fileExists(atPath: docsPath) ? docsPath : tempPath
                items.append(.audio(resolvedPath))
            case .description(let ctx):
                items.append(.description(ctx))
            }
        }

        return ActiveScanMedia(items: items)
    }
}
