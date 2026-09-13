import Foundation

struct CommunityIdentificationFeedResponse: Decodable {
    let data: [CommunityIdentificationFeedItem]
}

struct CommunityIdentificationActivityResponse: Decodable {
    let data: [CommunityIdentificationActivityItem]
}

enum CommunityIdentificationFeedScope: String, CaseIterable, Hashable {
    case all
    case mine

    var title: String {
        switch self {
        case .all:
            "All"
        case .mine:
            "Yours"
        }
    }
}

enum CommunityIdentificationRequestGroup: String, CaseIterable, Codable, Hashable {
    case all
    case plants
    case birds
    case insects
    case fungi
    case mammals
    case reptilesAmphibians = "reptiles_amphibians"

    var title: String {
        switch self {
        case .all:
            "All"
        case .plants:
            "Plants"
        case .birds:
            "Birds"
        case .insects:
            "Insects"
        case .fungi:
            "Fungi"
        case .mammals:
            "Mammals"
        case .reptilesAmphibians:
            "Herps"
        }
    }
}

struct CommunityIdentificationDetailResponse: Decodable {
    let data: CommunityIdentificationDetail
}

struct CommunityTaxonSearchResponse: Decodable {
    let data: [CommunityTaxonSearchResult]
}

struct CommunityIdentificationRequestResponse: Decodable {
    let success: Bool
    let data: CommunityIdentificationRequest
}

struct CommunityIdentificationMutationResponse: Decodable {
    let success: Bool
    let data: CommunityIdentificationMutation
}

struct CommunityIdentificationCursor: Equatable {
    let beforeRequestedAt: String?
    let beforeRequestId: String?

    static let empty = CommunityIdentificationCursor(
        beforeRequestedAt: nil,
        beforeRequestId: nil
    )

    var isEmpty: Bool {
        beforeRequestedAt == nil && beforeRequestId == nil
    }
}

struct CommunityIdentificationActivityCursor: Equatable {
    let beforeActivityAt: String?
    let beforeActivityId: String?

    static let empty = CommunityIdentificationActivityCursor(
        beforeActivityAt: nil,
        beforeActivityId: nil
    )

    var isEmpty: Bool {
        beforeActivityAt == nil && beforeActivityId == nil
    }
}

enum CommunityIdentificationRequestStatus: String, Decodable, Equatable {
    case needsId = "needs_id"
    case resolved
    case withdrawn
}

enum CommunityIdentificationActivityType: String, Decodable, Equatable {
    case suggestionBurst = "suggestion_burst"
    case consensusChanged = "consensus_changed"
    case resolved
}

enum CommunityIdentificationDisagreementMode: String, Codable, Equatable {
    case implicitSupport = "implicit_support"
    case explicitDisagreement = "explicit_disagreement"
    case maverick
}

enum CommunityTaxonPathRelationship: Equatable {
    case exact
    case descendant
    case ancestor
    case conflict
}

struct CommunityIdentificationFeedItem: Decodable, Identifiable, Equatable {
    let requestId: String
    let postId: String
    let scanId: String
    let heroImageUrl: String
    let requestedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let taxonomyVersionId: String?
    let projectionState: String?
    let consensusProcessingState: String?
    let currentTaxonId: String?
    let currentCommonName: String?
    let currentScientificName: String?
    let currentRank: String?
    let currentPath: String?
    let initialTaxonId: String?
    let initialCommonName: String?
    let initialScientificName: String?
    let initialRank: String?
    let initialPath: String?
    let requestGroup: CommunityIdentificationRequestGroup?
    let consensusScore: Double?
    let identificationCount: Int
    let viewerHasIdentified: Bool
    let publicLocationLabel: String?
    let locationSharing: ExplorePostLocationSharing?
    // swiftlint:disable:next implicit_optional_initialization
    var mediaItems: [ExploreMediaItem]? = nil

    var id: String { requestId }

    var resolvedMediaItems: [ExploreMediaItem] {
        guard let mediaItems, !mediaItems.isEmpty else {
            return [.legacyImage(url: heroImageUrl)]
        }
        return mediaItems
    }

    var hasVideoMedia: Bool {
        resolvedMediaItems.contains { $0.kind == .video }
    }

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: currentCommonName, scientificName: currentScientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(currentRank)
    }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }
}

struct CommunityIdentificationActivityItem: Decodable, Identifiable, Equatable {
    let activityId: String
    let activityType: CommunityIdentificationActivityType
    let requestId: String
    let postId: String
    let scanId: String
    let heroImageUrl: String?
    let activityAt: String
    let suggestionCount: Int
    let recentActorNames: [String]
    let taxonId: String?
    let taxonCommonName: String?
    let taxonScientificName: String?
    let taxonRank: String?
    let consensusScore: Double?
    let requestGroup: CommunityIdentificationRequestGroup?
    let mediaItems: [ExploreMediaItem]

    var id: String { activityId }

    var displayName: String {
        CommunityTaxonDisplay.name(
            commonName: taxonCommonName,
            scientificName: taxonScientificName
        )
    }

    var thumbnailUrl: String? {
        mediaItems.first?.posterImageUrl(fallback: heroImageUrl ?? "")
            ?? heroImageUrl
    }

    var activityDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: activityAt)
            ?? DateUtilities.iso8601Formatter.date(from: activityAt)
    }
}

struct CommunityIdentificationDetail: Decodable, Identifiable, Equatable {
    let requestId: String
    let postId: String
    let scanId: String
    let heroImageUrl: String
    let requestedAt: String
    let status: CommunityIdentificationRequestStatus
    let note: String?
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let authorIsPro: Bool?
    let taxonomyVersionId: String?
    let projectionState: String?
    let consensusProcessingState: String?
    let currentTaxonId: String?
    let currentCommonName: String?
    let currentScientificName: String?
    let currentRank: String?
    let currentPath: String?
    let initialTaxonId: String?
    let initialCommonName: String?
    let initialScientificName: String?
    let initialRank: String?
    let initialPath: String?
    let resolvedTaxonId: String?
    let consensusScore: Double?
    let identificationCount: Int
    let viewerIdentificationId: String?
    let publicLocationLabel: String?
    let locationSharing: ExplorePostLocationSharing?
    let inferenceTier: String?
    let suggestedTaxa: [CommunityTaxonSearchResult]?
    let identifications: [CommunityIdentification]
    // swiftlint:disable:next implicit_optional_initialization
    var mediaItems: [ExploreMediaItem]? = nil

    var id: String { requestId }

    var resolvedMediaItems: [ExploreMediaItem] {
        guard let mediaItems, !mediaItems.isEmpty else {
            return [.legacyImage(url: heroImageUrl)]
        }
        return mediaItems
    }

    var hasVideoMedia: Bool {
        resolvedMediaItems.contains { $0.kind == .video }
    }

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: currentCommonName, scientificName: currentScientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(currentRank)
    }

    var publicDisplayLocationLabel: String? {
        ExploreLocationPrivacy.displayLabel(from: publicLocationLabel)
    }

    var isConsensusUpdating: Bool {
        consensusProcessingState == "queued" || consensusProcessingState == "processing"
    }

    var activeIdentificationCount: Int {
        identifications.filter { $0.withdrawnAt == nil }.count
    }
}

struct CommunityIdentification: Decodable, Identifiable, Equatable {
    let id: String
    let userId: String
    let authorName: String
    let authorAvatarUrl: String?
    let taxonId: String
    let taxonomyVersionId: String?
    let commonName: String?
    let scientificName: String
    let rank: String
    let disagreementMode: CommunityIdentificationDisagreementMode
    let roleLabel: String?
    let isGenusBestPossible: Bool
    let reasoning: String?
    let createdAt: String
    let withdrawnAt: String?
    let isViewer: Bool

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: commonName, scientificName: scientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(rank)
    }
}

struct CommunityTaxonSearchResult: Decodable, Identifiable, Equatable {
    let taxonId: String
    let taxonomyVersionId: String?
    let commonName: String?
    let scientificName: String
    let rank: String
    let path: String
    let speciesId: String?
    let gbifTaxonKey: Int?
    let source: String?
    let isInDictionary: Bool?
    let acceptedGbifTaxonKey: Int?
    let taxonomicStatus: String?
    let suggestionSource: CommunityTaxonSuggestionSource?
    let confidenceScore: Double?
    let distinguishingFeature: String?

    init(
        taxonId: String,
        taxonomyVersionId: String?,
        commonName: String?,
        scientificName: String,
        rank: String,
        path: String,
        speciesId: String?,
        gbifTaxonKey: Int? = nil,
        source: String? = nil,
        isInDictionary: Bool? = nil,
        acceptedGbifTaxonKey: Int? = nil,
        taxonomicStatus: String? = nil,
        suggestionSource: CommunityTaxonSuggestionSource? = nil,
        confidenceScore: Double? = nil,
        distinguishingFeature: String? = nil
    ) {
        self.taxonId = taxonId
        self.taxonomyVersionId = taxonomyVersionId
        self.commonName = commonName
        self.scientificName = scientificName
        self.rank = rank
        self.path = path
        self.speciesId = speciesId
        self.gbifTaxonKey = gbifTaxonKey
        self.source = source
        self.isInDictionary = isInDictionary
        self.acceptedGbifTaxonKey = acceptedGbifTaxonKey
        self.taxonomicStatus = taxonomicStatus
        self.suggestionSource = suggestionSource
        self.confidenceScore = confidenceScore
        self.distinguishingFeature = distinguishingFeature
    }

    var id: String { taxonId }

    var displayName: String {
        CommunityTaxonDisplay.name(commonName: commonName, scientificName: scientificName)
    }

    var displayRank: String {
        CommunityTaxonDisplay.rankTitle(rank)
    }

    func relationship(to currentPath: String?) -> CommunityTaxonPathRelationship {
        guard let currentPath, !currentPath.isEmpty else { return .conflict }
        if path == currentPath { return .exact }
        if path.hasPrefix(currentPath + ".") { return .descendant }
        if currentPath.hasPrefix(path + ".") { return .ancestor }
        return .conflict
    }
}

enum CommunityTaxonSuggestionSource: String, Decodable, Equatable {
    case aiInitial = "ai_initial"
    case aiCandidate = "ai_candidate"

    var displayLabel: String {
        switch self {
        case .aiInitial:
            "AI suggestion"
        case .aiCandidate:
            "Alternative from scan analysis"
        }
    }
}

struct CommunityIdentificationRequest: Decodable, Equatable {
    let id: String
    let postId: String
    let scanId: String
    let requestedBy: String
    let requestedAt: String
    let status: CommunityIdentificationRequestStatus
    let note: String?
    let initialTaxonNodeId: String?
    let taxonomyVersionId: String?
    let currentCommunityTaxonNodeId: String?
    let resolvedTaxonNodeId: String?
    let consensusScore: Double?
    let consensusIdentificationCount: Int
    let consensusRank: String?
    let consensusProcessingState: String?
}

struct CommunityIdentificationMutation: Decodable, Equatable {
    let id: String
    let requestId: String
    let postId: String
    let userId: String
    let taxonNodeId: String
    let disagreementMode: CommunityIdentificationDisagreementMode
    let isGenusBestPossible: Bool
    let reasoning: String?
    let createdAt: String
    let withdrawnAt: String?
    let restoredAt: String?
}

struct CommunityRequestUpdateResponse: Decodable, Equatable {
    let success: Bool
    let data: CommunityRequestUpdate
}

struct CommunityRequestUpdate: Decodable, Equatable {
    let id: String
    let postId: String
    let note: String?
    let locationSharing: ExplorePostLocationSharing
    let updatedAt: String
}

enum CommunityTaxonDisplay {
    static func name(commonName: String?, scientificName: String?) -> String {
        if let commonName = commonName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !commonName.isEmpty {
            return commonName
        }
        if let scientificName = scientificName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !scientificName.isEmpty {
            return scientificName
        }
        return "Unknown taxon"
    }

    static func rankTitle(_ rank: String?) -> String {
        guard let rank else { return "Taxon" }
        switch rank.lowercased() {
        case "kingdom": return "Kingdom"
        case "phylum": return "Phylum"
        case "class": return "Class"
        case "order": return "Order"
        case "family": return "Family"
        case "genus": return "Genus"
        case "species": return "Species"
        default: return "Taxon"
        }
    }
}
