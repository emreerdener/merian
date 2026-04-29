import Foundation

/// A serializable representation of captured media elements, preserving chronological order
/// across image, audio, and textual modalities for persistent storage.
enum SerializedMediaItem: Codable, Equatable {
    case image(String)
    case audio(String)
    case description(ObservationContext)
}

enum CapturedMediaKind: String, Sendable, Equatable {
    case audio
    case describe
    case audioAndDescribe
    case other
}

struct CapturedMediaSummary: Sendable, Equatable {
    let hasImage: Bool
    let hasAudio: Bool
    let hasDescription: Bool

    static let empty = CapturedMediaSummary(hasImage: false, hasAudio: false, hasDescription: false)

    var hasNonVisualMedia: Bool {
        hasAudio || hasDescription
    }

    var isNonVisualOnly: Bool {
        !hasImage && hasNonVisualMedia
    }

    var preferredThumbnailKind: CapturedMediaKind? {
        switch (hasAudio, hasDescription) {
        case (true, true):
            return .audioAndDescribe
        case (true, false):
            return .audio
        case (false, true):
            return .describe
        case (false, false):
            return nil
        }
    }
}

/// Canonical decoder for persisted media JSON shared by live and historic scan flows.
enum MediaJSONParser {
    static func serializedItems(jsonString: String) -> [SerializedMediaItem]? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData)
    }

    static func imagePaths(jsonString: String) -> [String] {
        serializedItems(jsonString: jsonString)?.compactMap { item in
            guard case .image(let path) = item else { return nil }
            return path
        } ?? []
    }

    static func primaryImagePath(jsonString: String) -> String? {
        imagePaths(jsonString: jsonString).first
    }

    static func audioPaths(jsonString: String) -> [String] {
        serializedItems(jsonString: jsonString)?.compactMap { item in
            guard case .audio(let path) = item else { return nil }
            return path
        } ?? []
    }

    static func hasCloudImage(jsonString: String) -> Bool {
        imagePaths(jsonString: jsonString).contains { $0.starts(with: "http") }
    }

    static func modalitySummary(jsonString: String) -> CapturedMediaSummary {
        guard let items = serializedItems(jsonString: jsonString) else {
            return .empty
        }

        var hasImage = false
        var hasAudio = false
        var hasDescription = false

        for item in items {
            switch item {
            case .image:
                hasImage = true
            case .audio:
                hasAudio = true
            case .description:
                hasDescription = true
            }
        }

        return CapturedMediaSummary(
            hasImage: hasImage,
            hasAudio: hasAudio,
            hasDescription: hasDescription
        )
    }

    static func parse(jsonString: String) -> ActiveScanMedia? {
        guard let serializedItems = serializedItems(jsonString: jsonString) else {
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
