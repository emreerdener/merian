import Foundation
import SwiftData

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
enum SerializedMediaItem: Codable, Equatable, Sendable {
    case image(StoredMediaReference)
    case audio(StoredMediaReference)
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

    var observationContexts: [ObservationContext] {
        items.compactMap { item in
            guard case .description(let context) = item else { return nil }
            return context
        }
    }

    var imagePaths: [String] {
        imageReferences.map(\.serializedPath)
    }

    var audioPaths: [String] {
        audioReferences.map(\.serializedPath)
    }

    var observationContextsJSON: [String]? {
        let encoded = observationContexts.compactMap { context in
            (try? JSONEncoder().encode(context)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return encoded.isEmpty ? nil : encoded
    }

    var primaryImagePath: String? {
        imagePaths.first
    }

    var hasCloudImage: Bool {
        imageReferences.contains { $0.isRemote }
    }

    var descriptionText: String? {
        observationContexts.first(where: { !$0.isEmpty })?.serialized()
    }

    var summary: CapturedMediaSummary {
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

    var activeScanMedia: ActiveScanMedia {
        let resolvedItems: [MediaItem] = items.compactMap { serialized in
            switch serialized {
            case .image(let reference):
                return .image(reference.serializedPath)
            case .audio(let reference):
                return .audio(reference.resolvedLocalPath ?? reference.serializedPath)
            case .description(let context):
                return .description(context)
            }
        }

        return ActiveScanMedia(items: resolvedItems)
    }
}

enum PersistedCapturedMediaKind: String, Codable, Sendable {
    case image
    case audio
    case description
}

@Model
public final class CapturedMediaEntry {
    @Attribute(.unique) public var id: String
    public var orderIndex: Int
    public var kindRaw: String
    public var storageRaw: String
    public var mediaPath: String
    public var observationContextJSON: String

    init(
        id: String = UUID().uuidString,
        orderIndex: Int,
        item: SerializedMediaItem
    ) {
        self.id = id
        self.orderIndex = orderIndex

        switch item {
        case .image(let reference):
            self.kindRaw = PersistedCapturedMediaKind.image.rawValue
            self.storageRaw = reference.storage.rawValue
            self.mediaPath = reference.serializedPath
            self.observationContextJSON = ""
        case .audio(let reference):
            self.kindRaw = PersistedCapturedMediaKind.audio.rawValue
            self.storageRaw = reference.storage.rawValue
            self.mediaPath = reference.serializedPath
            self.observationContextJSON = ""
        case .description(let context):
            self.kindRaw = PersistedCapturedMediaKind.description.rawValue
            self.storageRaw = ""
            self.mediaPath = ""
            let contextData = try? JSONEncoder().encode(context)
            self.observationContextJSON = contextData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    var kind: PersistedCapturedMediaKind? {
        PersistedCapturedMediaKind(rawValue: kindRaw)
    }

    var serializedItem: SerializedMediaItem? {
        switch kind {
        case .image:
            guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                return nil
            }
            return .image(StoredMediaReference(storage: storage, path: mediaPath))
        case .audio:
            guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                return nil
            }
            return .audio(StoredMediaReference(storage: storage, path: mediaPath))
        case .description:
            guard let contextData = observationContextJSON.data(using: .utf8),
                  let context = try? JSONDecoder().decode(ObservationContext.self, from: contextData) else {
                return nil
            }
            return .description(context)
        case .none:
            return nil
        }
    }
}

extension CapturedMediaEntry {
    static func makeEntries(from items: [SerializedMediaItem]) -> [CapturedMediaEntry] {
        items.enumerated().map { index, item in
            CapturedMediaEntry(orderIndex: index, item: item)
        }
    }

    static func serializedItems(from entries: [CapturedMediaEntry]) -> [SerializedMediaItem] {
        entries
            .sorted { lhs, rhs in
                if lhs.orderIndex == rhs.orderIndex {
                    return lhs.id < rhs.id
                }
                return lhs.orderIndex < rhs.orderIndex
            }
            .compactMap(\.serializedItem)
    }
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

    static func observationContexts(jsonString: String) -> [ObservationContext] {
        CapturedMediaSnapshot(jsonString: jsonString).observationContexts
    }

    static func hasCloudImage(jsonString: String) -> Bool {
        CapturedMediaSnapshot(jsonString: jsonString).hasCloudImage
    }

    static func modalitySummary(jsonString: String) -> CapturedMediaSummary {
        CapturedMediaSnapshot(jsonString: jsonString).summary
    }

    static func parse(jsonString: String) -> ActiveScanMedia? {
        let snapshot = CapturedMediaSnapshot(jsonString: jsonString)
        guard !snapshot.items.isEmpty else {
            return nil
        }
        return snapshot.activeScanMedia
    }
}

private func firstImagePath(in items: [SerializedMediaItem]) -> String? {
    for item in items {
        if case .image(let reference) = item {
            return reference.serializedPath
        }
    }
    return nil
}

private func replaceCapturedMediaEntries(
    on record: LocalScanRecord,
    items: [SerializedMediaItem]
) {
    let newEntries = CapturedMediaEntry.makeEntries(from: items)

    if let context = record.modelContext {
        for existingEntry in record.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }
    }

    record.capturedMediaEntries = newEntries
}

private func replaceCapturedMediaEntries(
    on queuedScan: OfflineQueuedScan,
    items: [SerializedMediaItem]
) {
    let newEntries = CapturedMediaEntry.makeEntries(from: items)

    if let context = queuedScan.modelContext {
        for existingEntry in queuedScan.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }
    }

    queuedScan.capturedMediaEntries = newEntries
}

extension LocalScanRecord {
    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: serializedCapturedMediaItems)
    }

    var serializedCapturedMediaItems: [SerializedMediaItem] {
        if let capturedMediaEntries, !capturedMediaEntries.isEmpty {
            return CapturedMediaEntry.serializedItems(from: capturedMediaEntries)
        }
        guard let capturedMediaJSON else { return [] }
        return MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) ?? []
    }

    func replaceCapturedMedia(with items: [SerializedMediaItem]) {
        capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        coverImagePath = firstImagePath(in: items)
        replaceCapturedMediaEntries(on: self, items: items)
    }
}

extension OfflineQueuedScan {
    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: serializedCapturedMediaItems)
    }

    var serializedCapturedMediaItems: [SerializedMediaItem] {
        if let capturedMediaEntries, !capturedMediaEntries.isEmpty {
            return CapturedMediaEntry.serializedItems(from: capturedMediaEntries)
        }
        guard let capturedMediaJSON else { return [] }
        return MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) ?? []
    }

    func replaceCapturedMedia(with items: [SerializedMediaItem]) {
        capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        coverImagePath = firstImagePath(in: items)
        replaceCapturedMediaEntries(on: self, items: items)
    }
}
