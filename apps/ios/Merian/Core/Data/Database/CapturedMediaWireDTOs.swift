import Foundation

// BEGIN GENERATED: CapturedMedia wire DTOs
// Generated from services/supabase/functions/_shared/capturedMediaContract.ts.
// Do not edit this block by hand; run make generate-captured-media-dto-contract.

private struct CapturedMediaWireCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == CapturedMediaWireCodingKey {
    func requireAllowedKeys(_ allowed: Set<String>, path: String) throws {
        if let unexpected = allKeys.map(\.stringValue).first(where: { !allowed.contains($0) }) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "\(path) contains unexpected key '\(unexpected)'."
            ))
        }
    }
}

private struct CapturedMediaWirePayloadEnvelope<Value: Decodable>: Decodable {
    let value: Value

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(["_0"], path: "captured_media payload")
        guard let key = CapturedMediaWireCodingKey(stringValue: "_0"), container.contains(key) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media payload is missing _0."
            ))
        }
        value = try container.decode(Value.self, forKey: key)
    }
}

enum CapturedMediaWireStorageDTO: String, Decodable, Sendable {
    case remoteURL
    case localFile
}

struct CapturedMediaStoredReferenceDTO: Decodable, Sendable {
    let storage: CapturedMediaWireStorageDTO
    let path: String
    let sourceIndex: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(
            ["storage", "path", "sourceIndex", "source_index"],
            path: "captured_media reference"
        )
        let storageKey = CapturedMediaWireCodingKey(stringValue: "storage")!
        let pathKey = CapturedMediaWireCodingKey(stringValue: "path")!
        let sourceIndexKey = CapturedMediaWireCodingKey(stringValue: "sourceIndex")!
        let sourceIndexSnakeKey = CapturedMediaWireCodingKey(stringValue: "source_index")!
        guard !(container.contains(sourceIndexKey) && container.contains(sourceIndexSnakeKey)) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media reference contains both source-index aliases."
            ))
        }

        storage = try container.decode(CapturedMediaWireStorageDTO.self, forKey: storageKey)
        let decodedPath = try container.decode(String.self, forKey: pathKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedPath.isEmpty,
              decodedPath.count <= 4096 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media reference path is outside the V1 bound."
            ))
        }
        if storage == .remoteURL {
            guard let components = URLComponents(string: decodedPath),
                  components.scheme?.lowercased() == "https",
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "captured_media remote reference must use a credential-free HTTPS URL."
                ))
            }
        }
        path = decodedPath

        let decodedSourceIndex = try container.decodeIfPresent(Int.self, forKey: sourceIndexKey)
            ?? container.decodeIfPresent(Int.self, forKey: sourceIndexSnakeKey)
        if let decodedSourceIndex,
           !(0...63).contains(decodedSourceIndex) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media sourceIndex is outside the V1 bound."
            ))
        }
        sourceIndex = decodedSourceIndex
    }
}

struct CapturedMediaVideoReferenceDTO: Decodable, Sendable {
    let video: CapturedMediaStoredReferenceDTO
    let thumbnail: CapturedMediaStoredReferenceDTO?
    let audio: CapturedMediaStoredReferenceDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(
            ["video", "thumbnail", "audio"],
            path: "captured_media video"
        )
        video = try container.decode(
            CapturedMediaStoredReferenceDTO.self,
            forKey: CapturedMediaWireCodingKey(stringValue: "video")!
        )
        thumbnail = try container.decodeIfPresent(
            CapturedMediaStoredReferenceDTO.self,
            forKey: CapturedMediaWireCodingKey(stringValue: "thumbnail")!
        )
        audio = try container.decodeIfPresent(
            CapturedMediaStoredReferenceDTO.self,
            forKey: CapturedMediaWireCodingKey(stringValue: "audio")!
        )
    }
}

struct CapturedMediaDescriptionDTO: Decodable, Sendable {
    let freeText: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(
            ["freeText", "free_text", "addedAt", "added_at"],
            path: "captured_media description"
        )
        let freeTextKey = CapturedMediaWireCodingKey(stringValue: "freeText")!
        let freeTextSnakeKey = CapturedMediaWireCodingKey(stringValue: "free_text")!
        guard !(container.contains(freeTextKey) && container.contains(freeTextSnakeKey)) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media description contains both free-text aliases."
            ))
        }
        let decodedText: String
        if container.contains(freeTextKey) {
            decodedText = try container.decode(String.self, forKey: freeTextKey)
        } else {
            decodedText = try container.decode(String.self, forKey: freeTextSnakeKey)
        }
        let normalizedText = decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              normalizedText.count <= 8192 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media description text is outside the V1 bound."
            ))
        }
        freeText = normalizedText
        // Legacy addedAt/added_at values are intentionally ignored without decoding.
        // Completed ordering is owned by manifest array order, not this retired field.
    }
}

enum CapturedMediaWireItemDTO: Decodable, Sendable {
    case image(CapturedMediaStoredReferenceDTO)
    case audio(CapturedMediaStoredReferenceDTO)
    case video(CapturedMediaVideoReferenceDTO)
    case description(CapturedMediaDescriptionDTO)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first,
              ["image", "audio", "video", "description"].contains(key.stringValue) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media item must contain exactly one known variant."
            ))
        }
        switch key.stringValue {
        case "image":
            self = .image(
                try container.decode(
                    CapturedMediaWirePayloadEnvelope<CapturedMediaStoredReferenceDTO>.self,
                    forKey: key
                ).value
            )
        case "audio":
            self = .audio(
                try container.decode(
                    CapturedMediaWirePayloadEnvelope<CapturedMediaStoredReferenceDTO>.self,
                    forKey: key
                ).value
            )
        case "video":
            self = .video(
                try container.decode(
                    CapturedMediaWirePayloadEnvelope<CapturedMediaVideoReferenceDTO>.self,
                    forKey: key
                ).value
            )
        case "description":
            self = .description(
                try container.decode(
                    CapturedMediaWirePayloadEnvelope<CapturedMediaDescriptionDTO>.self,
                    forKey: key
                ).value
            )
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media item contains an unknown variant."
            ))
        }
    }
}

struct CapturedMediaWireManifestDTO: Decodable, Sendable {
    let items: [CapturedMediaWireItemDTO]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decodedItems: [CapturedMediaWireItemDTO] = []
        decodedItems.reserveCapacity(min(container.count ?? 0, 64))
        while !container.isAtEnd {
            guard decodedItems.count < 64 else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "captured_media exceeds the V1 item bound."
                ))
            }
            decodedItems.append(try container.decode(CapturedMediaWireItemDTO.self))
        }
        // Legacy rows may contain an empty array instead of SQL null. Treat it
        // as a missing manifest so compatibility URL/context columns can hydrate.
        items = decodedItems
    }
}
// END GENERATED: CapturedMedia wire DTOs

// MARK: - Domain Mapping

extension CapturedMediaStoredReferenceDTO {
    var remoteStoredMediaReference: StoredMediaReference? {
        guard storage == .remoteURL else { return nil }
        return .remoteURL(path, sourceIndex: sourceIndex)
    }
}

extension CapturedMediaWireItemDTO {
    var serializedMediaItem: SerializedMediaItem? {
        switch self {
        case .image(let reference):
            return reference.remoteStoredMediaReference.map(SerializedMediaItem.image)
        case .audio(let reference):
            return reference.remoteStoredMediaReference.map(SerializedMediaItem.audio)
        case .video(let reference):
            guard let video = reference.video.remoteStoredMediaReference else {
                return nil
            }
            return .video(StoredVideoMediaReference(
                video: video,
                thumbnail: reference.thumbnail?.remoteStoredMediaReference,
                audio: reference.audio?.remoteStoredMediaReference
            ))
        case .description(let context):
            return .description(ObservationContext(freeText: context.freeText))
        }
    }
}

extension CapturedMediaWireManifestDTO {
    var serializedMediaItems: [SerializedMediaItem] {
        items.compactMap(\.serializedMediaItem)
    }
}
