import Foundation

enum MediaStorageLocation: String, Codable, Sendable, Equatable {
    case documents
    case remoteURL
    case absolutePath
}

/// Canonical persisted reference to a captured media asset.
///
/// New payloads encode both the path and how it should be resolved. The custom decoder
/// also accepts the legacy single-string representation so older scans continue to load.
struct StoredMediaReference: Codable, Equatable, Sendable {
    let storage: MediaStorageLocation
    let path: String

    init(storage: MediaStorageLocation, path: String) {
        self.storage = storage
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(legacyPath: String) {
        let normalizedPath = legacyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPath.starts(with: "http://") || normalizedPath.starts(with: "https://") {
            self.init(storage: .remoteURL, path: normalizedPath)
        } else if normalizedPath.hasPrefix("/") || normalizedPath.starts(with: "file://") {
            self.init(storage: .absolutePath, path: normalizedPath)
        } else {
            self.init(storage: .documents, path: normalizedPath)
        }
    }

    static func documents(_ path: String) -> Self {
        Self(storage: .documents, path: path)
    }

    static func remoteURL(_ path: String) -> Self {
        Self(storage: .remoteURL, path: path)
    }

    static func absolutePath(_ path: String) -> Self {
        Self(storage: .absolutePath, path: path)
    }

    var serializedPath: String {
        path
    }

    var isRemote: Bool {
        storage == .remoteURL
    }

    var resolvedURL: URL? {
        switch storage {
        case .documents:
            return URL.documentsDirectory.appendingPathComponent(path)
        case .remoteURL:
            return URL(string: path)
        case .absolutePath:
            if path.starts(with: "file://") {
                return URL(string: path)
            }
            return URL(fileURLWithPath: path)
        }
    }

    var resolvedLocalPath: String? {
        switch storage {
        case .documents:
            let documentsPath = URL.documentsDirectory.appendingPathComponent(path).path
            if FileManager.default.fileExists(atPath: documentsPath) {
                return documentsPath
            }
            return FileManager.default.temporaryDirectory.appendingPathComponent(path).path
        case .absolutePath:
            return resolvedURL?.path
        case .remoteURL:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case storage
        case path
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let legacyPath = try? container.decode(String.self) {
            self.init(legacyPath: legacyPath)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storage = try container.decode(MediaStorageLocation.self, forKey: .storage)
        let path = try container.decode(String.self, forKey: .path)
        self.init(storage: storage, path: path)
    }
}

extension StoredMediaReference: ExpressibleByStringLiteral {
    init(stringLiteral value: StringLiteralType) {
        self.init(legacyPath: value)
    }
}

extension StoredMediaReference {
    static func == (lhs: StoredMediaReference, rhs: String) -> Bool {
        lhs.serializedPath == rhs
    }

    static func == (lhs: String, rhs: StoredMediaReference) -> Bool {
        lhs == rhs.serializedPath
    }
}

/// A serializable representation of captured media elements, preserving chronological order
/// across image, audio, and textual modalities for persistent storage.
enum SerializedMediaItem: Codable, Equatable {
    case image(StoredMediaReference)
    case audio(StoredMediaReference)
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
            guard case .image(let reference) = item else { return nil }
            return reference.serializedPath
        } ?? []
    }

    static func primaryImagePath(jsonString: String) -> String? {
        imagePaths(jsonString: jsonString).first
    }

    static func imageReferences(jsonString: String) -> [StoredMediaReference] {
        serializedItems(jsonString: jsonString)?.compactMap { item in
            guard case .image(let reference) = item else { return nil }
            return reference
        } ?? []
    }

    static func audioPaths(jsonString: String) -> [String] {
        serializedItems(jsonString: jsonString)?.compactMap { item in
            guard case .audio(let reference) = item else { return nil }
            return reference.serializedPath
        } ?? []
    }

    static func audioReferences(jsonString: String) -> [StoredMediaReference] {
        serializedItems(jsonString: jsonString)?.compactMap { item in
            guard case .audio(let reference) = item else { return nil }
            return reference
        } ?? []
    }

    static func observationContexts(jsonString: String) -> [ObservationContext] {
        serializedItems(jsonString: jsonString)?.compactMap { item in
            guard case .description(let context) = item else { return nil }
            return context
        } ?? []
    }

    static func hasCloudImage(jsonString: String) -> Bool {
        imageReferences(jsonString: jsonString).contains { $0.isRemote }
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
            case .image(let reference):
                items.append(.image(reference.serializedPath))
            case .audio(let reference):
                let resolvedPath = reference.resolvedLocalPath ?? reference.serializedPath
                items.append(.audio(resolvedPath))
            case .description(let ctx):
                items.append(.description(ctx))
            }
        }

        return ActiveScanMedia(items: items)
    }
}
