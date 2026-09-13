import CoreLocation
import Foundation

enum ExploreMapMode: String, Decodable {
    case clusters
    case posts
}

enum ExploreCoordinateVisibility: String, Decodable, Equatable {
    case exact
    case obscured
}

struct ExploreMapPointsResponse: Decodable {
    let mode: ExploreMapMode
    let visibleCount: Int
    let categoryCounts: [ExploreMapCategoryCount]
    let mediaTypeCounts: [ExploreMapMediaTypeCount]
    let clusters: [ExploreMapCluster]
    let posts: [ExploreMapPost]

    private enum CodingKeys: String, CodingKey {
        case mode
        case visibleCount
        case categoryCounts
        case mediaTypeCounts
        case clusters
        case posts
    }

    init(
        mode: ExploreMapMode,
        visibleCount: Int,
        categoryCounts: [ExploreMapCategoryCount] = [],
        mediaTypeCounts: [ExploreMapMediaTypeCount] = [],
        clusters: [ExploreMapCluster] = [],
        posts: [ExploreMapPost] = []
    ) {
        self.mode = mode
        self.visibleCount = visibleCount
        self.categoryCounts = categoryCounts
        self.mediaTypeCounts = mediaTypeCounts
        self.clusters = clusters
        self.posts = posts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(ExploreMapMode.self, forKey: .mode)
        visibleCount = try container.decode(Int.self, forKey: .visibleCount)
        categoryCounts = try container.decodeIfPresent([ExploreMapCategoryCount].self, forKey: .categoryCounts) ?? []
        mediaTypeCounts = try container.decodeIfPresent([ExploreMapMediaTypeCount].self, forKey: .mediaTypeCounts) ?? []
        clusters = try container.decode([ExploreMapCluster].self, forKey: .clusters)
        posts = try container.decode([ExploreMapPost].self, forKey: .posts)
    }
}

enum ExploreMapSpeciesCategory: String, Codable, CaseIterable, Identifiable {
    case plants
    case fungi
    case birds
    case mammals
    case reptiles
    case amphibians
    case fish
    case insects
    case arachnids
    case other

    static let defaultFilters: [ExploreMapSpeciesCategory] = [
        .birds,
        .insects,
        .plants,
        .fungi,
        .mammals,
        .reptiles,
        .amphibians,
        .fish,
        .arachnids,
        .other
    ]

    var id: String { rawValue }

    var sortPriority: Int {
        Self.defaultFilters.firstIndex(of: self) ?? Self.defaultFilters.count
    }

    var title: String {
        switch self {
        case .plants: return "Plants"
        case .fungi: return "Fungi"
        case .birds: return "Birds"
        case .mammals: return "Mammals"
        case .reptiles: return "Reptiles"
        case .amphibians: return "Amphibians"
        case .fish: return "Fish"
        case .insects: return "Insects"
        case .arachnids: return "Arachnids"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .plants: return "leaf"
        case .fungi: return "circle.hexagongrid"
        case .birds: return "bird"
        case .mammals: return "pawprint"
        case .reptiles: return "lizard"
        case .amphibians: return "drop"
        case .fish: return "fish"
        case .insects: return "ladybug"
        case .arachnids: return "ant"
        case .other: return "sparkle"
        }
    }
}

struct ExploreMapCategoryCount: Decodable, Identifiable, Equatable {
    let category: ExploreMapSpeciesCategory
    let count: Int

    var id: ExploreMapSpeciesCategory { category }
}

struct ExploreMapMediaTypeCount: Decodable, Identifiable, Equatable {
    let mediaType: ExploreMediaKind
    let count: Int

    var id: ExploreMediaKind { mediaType }
}

struct ExploreMapCluster: Decodable, Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let postCount: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ExploreMapPost: Decodable, Identifiable, Equatable {
    let postId: String
    let scanId: String
    let latitude: Double
    let longitude: Double
    let coordinateVisibility: ExploreCoordinateVisibility
    @ExploreEmptyStringIfMissing var heroImageUrl: String
    // swiftlint:disable:next implicit_optional_initialization
    var referenceThumbnailUrl: String? = nil
    let sharedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let speciesCommonName: String
    let speciesScientificName: String
    let petIdentification: PetIdentification?
    let taxonomyKingdom: String?
    let taxonomyClass: String?
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

    var mapThumbnailUrl: String {
        let visualMedia = mediaItems?.first { item in
            item.kind == .image && item.posterImageUrl(fallback: "") != nil
        }
        if let visualUrl = visualMedia?.posterImageUrl(fallback: "") {
            return visualUrl
        }

        let videoThumbnail = mediaItems?
            .first { $0.kind == .video }?
            .thumbnailUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let videoThumbnail, !videoThumbnail.isEmpty {
            return videoThumbnail
        }

        let referenceThumbnail = referenceThumbnailUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let referenceThumbnail, !referenceThumbnail.isEmpty {
            return referenceThumbnail
        }

        return heroImageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }

    var asExplorePost: ExplorePost {
        ExplorePost(
            postId: postId,
            scanId: scanId,
            heroImageUrl: heroImageUrl,
            referenceThumbnailUrl: referenceThumbnailUrl,
            sharedAt: sharedAt,
            authorUserId: authorUserId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorAvatarUrl: authorAvatarUrl,
            authorIsPro: authorIsPro,
            hashtags: nil,
            speciesCommonName: speciesCommonName,
            speciesScientificName: speciesScientificName,
            petIdentification: petIdentification,
            publicLocationLabel: publicLocationLabel,
            locationSharing: locationSharing,
            timeOfDay: timeOfDay,
            currentMonth: currentMonth,
            weatherCondition: weatherCondition,
            weatherTemperatureF: weatherTemperatureF,
            likeCount: likeCount,
            commentCount: commentCount,
            viewerHasLiked: viewerHasLiked,
            isOwnedByViewer: isOwnedByViewer,
            rankingValue: nil,
            mediaItems: mediaItems
        )
    }
}
