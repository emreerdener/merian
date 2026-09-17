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
    /// Stable ordinal from the original standalone-media submission.
    ///
    /// This is intentionally optional: legacy manifests and compatibility URL
    /// arrays do not prove which original clip a durable URL represents.
    let sourceIndex: Int?

    init(
        storage: MediaStorageLocation,
        path: String,
        sourceIndex: Int? = nil
    ) {
        self.storage = storage
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceIndex = sourceIndex.flatMap { $0 >= 0 ? $0 : nil }
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

    static func documents(_ path: String, sourceIndex: Int? = nil) -> Self {
        Self(storage: .documents, path: path, sourceIndex: sourceIndex)
    }

    static func remoteURL(_ path: String, sourceIndex: Int? = nil) -> Self {
        Self(storage: .remoteURL, path: path, sourceIndex: sourceIndex)
    }

    static func absolutePath(_ path: String, sourceIndex: Int? = nil) -> Self {
        Self(storage: .absolutePath, path: path, sourceIndex: sourceIndex)
    }

    var serializedPath: String {
        path
    }

    var isRemote: Bool {
        storage == .remoteURL
    }

    private enum CodingKeys: String, CodingKey {
        case storage
        case path
        case sourceIndex
        case sourceIndexSnake = "source_index"
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
        let sourceIndex = (try? container.decode(Int.self, forKey: .sourceIndex))
            ?? (try? container.decode(Int.self, forKey: .sourceIndexSnake))
        self.init(storage: storage, path: path, sourceIndex: sourceIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storage, forKey: .storage)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(sourceIndex, forKey: .sourceIndex)
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

struct StoredVideoMediaReference: Codable, Equatable, Sendable {
    let video: StoredMediaReference
    let thumbnail: StoredMediaReference?
    let audio: StoredMediaReference?

    init(
        video: StoredMediaReference,
        thumbnail: StoredMediaReference? = nil,
        audio: StoredMediaReference? = nil
    ) {
        self.video = video
        self.thumbnail = thumbnail
        self.audio = audio
    }

    init(
        _ legacyReference: StoredMediaReference,
        thumbnail: StoredMediaReference? = nil,
        audio: StoredMediaReference? = nil
    ) {
        self.init(video: legacyReference, thumbnail: thumbnail, audio: audio)
    }

    var serializedPath: String {
        video.serializedPath
    }

    private enum CodingKeys: String, CodingKey {
        case video
        case thumbnail
        case audio
    }

    init(from decoder: Decoder) throws {
        if let legacyReference = try? StoredMediaReference(from: decoder) {
            self.init(legacyReference)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let video = try container.decode(StoredMediaReference.self, forKey: .video)
        let thumbnail = try container.decodeIfPresent(StoredMediaReference.self, forKey: .thumbnail)
        let audio = try container.decodeIfPresent(StoredMediaReference.self, forKey: .audio)
        self.init(video: video, thumbnail: thumbnail, audio: audio)
    }
}

/// A serializable representation of captured media elements, preserving chronological order
/// across image, audio, and textual modalities for persistent storage.
enum SerializedMediaItem: Codable, Equatable, Sendable {
    case image(StoredMediaReference)
    case audio(StoredMediaReference)
    case video(StoredVideoMediaReference)
    case description(ObservationContext)
}

struct CapturedMediaSnapshot: Equatable, Sendable {
    let items: [SerializedMediaItem]

    init(items: [SerializedMediaItem] = []) {
        self.items = items
    }

    init(jsonString: String?) {
        guard let jsonString,
              let items = MediaJSONParser.serializedItems(jsonString: jsonString) else {
            self.items = []
            return
        }
        self.items = items
    }

    var jsonString: String? {
        MediaJSONParser.jsonString(from: items)
    }

    var imageReferences: [StoredMediaReference] {
        items.compactMap { item in
            guard case .image(let reference) = item else { return nil }
            return reference
        }
    }

    var audioReferences: [StoredMediaReference] {
        items.compactMap { item in
            guard case .audio(let reference) = item else { return nil }
            return reference
        }
    }

    var videoAudioReferences: [StoredMediaReference] {
        videoMediaReferences.compactMap(\.audio)
    }

    /// Audio candidates that can seed a historical refinement, in the same
    /// precedence order as the original capture surface. Standalone recordings
    /// win; legacy extracted video companions remain a compatibility fallback.
    var refinementAudioReferences: [StoredMediaReference] {
        var seenReferences = Set<String>()
        return (audioReferences + videoAudioReferences).filter { reference in
            let identity = "\(reference.storage.rawValue)\u{0}\(reference.path)"
            return seenReferences.insert(identity).inserted
        }
    }

    var videoReferences: [StoredMediaReference] {
        items.compactMap { item in
            guard case .video(let reference) = item else { return nil }
            return reference.video
        }
    }

    var videoMediaReferences: [StoredVideoMediaReference] {
        items.compactMap { item in
            guard case .video(let reference) = item else { return nil }
            return reference
        }
    }

    var videoThumbnailReferences: [StoredMediaReference] {
        videoMediaReferences.compactMap(\.thumbnail)
    }

    var observationContexts: [ObservationContext] {
        items.compactMap { item in
            guard case .description(let context) = item else { return nil }
            return context
        }
    }

    var imagePaths: [String] {
        imageReferences.map(\.serializedPath)
    }

    var thumbnailImagePaths: [String] {
        var paths = imagePaths
        for thumbnailPath in videoThumbnailReferences.map(\.serializedPath) where !paths.contains(thumbnailPath) {
            paths.append(thumbnailPath)
        }
        return paths
    }

    var audioPaths: [String] {
        items.compactMap { item -> String? in
            switch item {
            case .audio(let reference):
                let path = reference.serializedPath
                return path.isEmpty ? nil : path
            case .video(let reference):
                guard !reference.video.serializedPath.isEmpty,
                      let path = reference.audio?.serializedPath,
                      !path.isEmpty else {
                    return nil
                }
                return path
            case .image, .description:
                return nil
            }
        }
    }

    var videoPaths: [String] {
        videoReferences.map(\.serializedPath)
    }

    var observationContextsJSON: [String]? {
        let encoded = observationContexts.compactMap { context in
            (try? JSONEncoder().encode(context)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return encoded.isEmpty ? nil : encoded
    }

    var primaryImagePath: String? {
        thumbnailImagePaths.first
    }

    var hasCloudImage: Bool {
        imageReferences.contains { $0.isRemote } || videoThumbnailReferences.contains { $0.isRemote }
    }

    var descriptionText: String? {
        observationContexts.first(where: { !$0.isEmpty })?.serialized()
    }

    var summary: CapturedMediaSummary {
        var hasImage = false
        var hasAudio = false
        var hasVideo = false
        var hasDescription = false

        for item in items {
            switch item {
            case .image:
                hasImage = true
            case .audio:
                hasAudio = true
            case .video(let reference):
                hasVideo = true
                if reference.audio != nil {
                    hasAudio = true
                }
            case .description:
                hasDescription = true
            }
        }

        return CapturedMediaSummary(
            hasImage: hasImage,
            hasAudio: hasAudio,
            hasVideo: hasVideo,
            hasDescription: hasDescription
        )
    }
}

enum CapturedMediaKind: String, Sendable, Equatable {
    case audio
    case video
    case describe
    case audioAndDescribe
    case other
}

struct CapturedMediaSummary: Sendable, Equatable {
    let hasImage: Bool
    let hasAudio: Bool
    let hasVideo: Bool
    let hasDescription: Bool

    static let empty = CapturedMediaSummary(hasImage: false, hasAudio: false, hasVideo: false, hasDescription: false)

    var hasNonVisualMedia: Bool {
        hasAudio || hasDescription
    }

    var isNonVisualOnly: Bool {
        !hasImage && hasNonVisualMedia
    }

    var preferredThumbnailKind: CapturedMediaKind? {
        if hasVideo { return .video }

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
    static func jsonString(from items: [SerializedMediaItem]) -> String? {
        guard !items.isEmpty,
              let data = try? JSONEncoder().encode(items) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func serializedItems(jsonString: String) -> [SerializedMediaItem]? {
        guard let jsonData = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([SerializedMediaItem].self, from: jsonData)
    }

    static func imagePaths(jsonString: String) -> [String] {
        CapturedMediaSnapshot(jsonString: jsonString).imagePaths
    }

    static func primaryImagePath(jsonString: String) -> String? {
        CapturedMediaSnapshot(jsonString: jsonString).primaryImagePath
    }

    static func imageReferences(jsonString: String) -> [StoredMediaReference] {
        CapturedMediaSnapshot(jsonString: jsonString).imageReferences
    }

    static func audioPaths(jsonString: String) -> [String] {
        CapturedMediaSnapshot(jsonString: jsonString).audioPaths
    }

    static func audioReferences(jsonString: String) -> [StoredMediaReference] {
        CapturedMediaSnapshot(jsonString: jsonString).audioReferences
    }

    static func videoPaths(jsonString: String) -> [String] {
        CapturedMediaSnapshot(jsonString: jsonString).videoPaths
    }

    static func videoReferences(jsonString: String) -> [StoredMediaReference] {
        CapturedMediaSnapshot(jsonString: jsonString).videoReferences
    }

    static func observationContexts(jsonString: String) -> [ObservationContext] {
        CapturedMediaSnapshot(jsonString: jsonString).observationContexts
    }

    static func hasCloudImage(jsonString: String) -> Bool {
        CapturedMediaSnapshot(jsonString: jsonString).hasCloudImage
    }

    static func modalitySummary(jsonString: String) -> CapturedMediaSummary {
        CapturedMediaSnapshot(jsonString: jsonString).summary
    }
}
