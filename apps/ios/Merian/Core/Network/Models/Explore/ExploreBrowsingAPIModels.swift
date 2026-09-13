import Foundation

@propertyWrapper
struct ExploreEmptyStringIfMissing: Decodable, Equatable {
    var wrappedValue: String

    init(wrappedValue: String) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? "" : try container.decode(String.self)
    }
}

extension KeyedDecodingContainer {
    func decode(
        _ type: ExploreEmptyStringIfMissing.Type,
        forKey key: Key
    ) throws -> ExploreEmptyStringIfMissing {
        try decodeIfPresent(type, forKey: key) ?? ExploreEmptyStringIfMissing(wrappedValue: "")
    }
}

struct ExploreFeedResponse: Decodable {
    let data: [ExplorePost]
}

struct ExplorePostResponse: Decodable {
    let data: ExplorePost
}

struct ExploreComposerMediaResponse: Decodable {
    let data: ExploreComposerMediaPayload
}

struct ExploreComposerMediaPayload: Decodable, Equatable {
    let scanId: String
    let postId: String?
    let mediaItems: [ExploreComposerMediaItem]
}

struct ExploreComposerMediaItem: Decodable, Equatable {
    let sourceMediaId: String
    let kind: ExploreMediaKind
    let url: String
    let thumbnailUrl: String
    let orderIndex: Int
    let isSelected: Bool?
    let selectionOrderIndex: Int?
}

enum ExploreMediaKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case image
    case video
    case audio

    var id: Self { self }

    static let feedFilterCases: [Self] = [.image, .audio, .video]

    var filterTitle: String {
        switch self {
        case .image: "Images"
        case .video: "Videos"
        case .audio: "Audio"
        }
    }

    var filterSymbolName: String {
        switch self {
        case .image: "photo"
        case .video: "video.fill"
        case .audio: "waveform"
        }
    }
}

struct ExploreMediaItem: Decodable, Equatable {
    let kind: ExploreMediaKind
    let url: String
    let thumbnailUrl: String?
    let orderIndex: Int
    let durationSeconds: Double?
    let hasAudio: Bool

    func posterImageUrl(fallback: String) -> String? {
        let thumbnail = thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let thumbnail, !thumbnail.isEmpty { return thumbnail }

        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? nil : fallback
    }

    var audioSpectrogramPosterUrl: String? {
        guard kind == .audio else { return nil }
        let thumbnail = thumbnailUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let thumbnail, !thumbnail.isEmpty else { return nil }
        return thumbnail
    }

    static func legacyImage(url: String) -> Self {
        ExploreMediaItem(
            kind: .image,
            url: url,
            thumbnailUrl: url,
            orderIndex: 0,
            durationSeconds: nil,
            hasAudio: false
        )
    }
}

struct ExploreAuthorProfileResponse: Decodable {
    let data: ExploreAuthorProfile
}

struct ExploreAuthorPostsResponse: Decodable {
    let data: [ExplorePost]
    let nextCursor: ExploreAuthorPostCursor?
}

struct ExploreHashtagPostsResponse: Decodable {
    let data: [ExplorePost]
}

struct ExploreSpeciesPostsResponse: Decodable, Equatable {
    let data: [ExplorePost]
    let nextCursor: ExploreSpeciesPostCursor?
}

struct ExploreFollowState: Decodable, Equatable {
    let success: Bool
    let authorUserId: String
    let followerCount: Int
    let followingCount: Int
    let viewerIsFollowing: Bool
}

struct ExplorePost: Decodable, Identifiable, Equatable {
    let postId: String
    let scanId: String
    @ExploreEmptyStringIfMissing var heroImageUrl: String
    // swiftlint:disable:next implicit_optional_initialization
    var referenceThumbnailUrl: String? = nil
    let sharedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let hashtags: [String]?
    let speciesCommonName: String
    let speciesScientificName: String
    let petIdentification: PetIdentification?
    let publicLocationLabel: String?
    let locationSharing: ExplorePostLocationSharing?
    let timeOfDay: String?
    let currentMonth: Int?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let isOwnedByViewer: Bool
    let rankingValue: Int?
    // swiftlint:disable:next implicit_optional_initialization
    var mediaItems: [ExploreMediaItem]? = nil

    var id: String { postId }

    var resolvedMediaItems: [ExploreMediaItem] {
        guard let mediaItems, !mediaItems.isEmpty else {
            return [.legacyImage(url: heroImageUrl)]
        }
        return mediaItems
    }

    var hasVideoMedia: Bool {
        resolvedMediaItems.contains { $0.kind == .video }
    }

    var hasAudioMedia: Bool {
        resolvedMediaItems.contains { $0.kind == .audio }
    }

    var gridThumbnailUrl: String {
        gridThumbnailUrl(localReferenceUrl: nil)
    }

    func gridThumbnailUrl(localReferenceUrl: String?) -> String {
        let serverReferenceUrl = referenceThumbnailUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localReferenceUrl = localReferenceUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReferenceUrl: String? = if let serverReferenceUrl, !serverReferenceUrl.isEmpty {
            serverReferenceUrl
        } else if let localReferenceUrl, !localReferenceUrl.isEmpty {
            localReferenceUrl
        } else {
            nil
        }

        if hasAudioMedia,
           let resolvedReferenceUrl {
            return resolvedReferenceUrl
        }
        return heroImageUrl
    }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }

    var sharedAtDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: sharedAt)
            ?? DateUtilities.iso8601Formatter.date(from: sharedAt)
    }
}
