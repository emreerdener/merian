import Foundation
import SwiftData

enum PersistedCapturedMediaKind: String, Codable, Sendable {
    case image
    case audio
    case video
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
        case .video(let reference):
            self.kindRaw = PersistedCapturedMediaKind.video.rawValue
            self.storageRaw = reference.video.storage.rawValue
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
        case .video:
            guard let storage = MediaStorageLocation(rawValue: storageRaw), !mediaPath.isEmpty else {
                return nil
            }
            return .video(StoredVideoMediaReference(StoredMediaReference(storage: storage, path: mediaPath)))
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
