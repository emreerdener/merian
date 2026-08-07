import Foundation

struct FieldTripsCatalogResponse: Decodable {
    let data: [FieldTripTemplate]
}

struct FieldTripCaptureContextResponse: Codable, Equatable, Sendable {
    let data: [FieldTripCaptureOuting]
}

struct FieldTripCaptureOuting: Codable, Equatable, Identifiable, Sendable {
    let userFieldTripId: String
    let templateId: String
    let templateSlug: String
    let outingTitle: String
    let lastEngagedAt: String
    let levelNumber: Int
    let levelTitle: String
    let completedCount: Int
    let targetCount: Int
    let targets: [FieldTripCaptureTarget]

    var id: String { userFieldTripId }
}

struct FieldTripCaptureTarget: Codable, Equatable, Identifiable, Sendable {
    let itemId: String
    let prompt: String
    let sortOrder: Int
    let hasGuide: Bool

    var id: String { itemId }
}

struct FieldTripTemplateDetailResponse: Decodable {
    let data: FieldTripTemplate
}

struct FieldTripStartResponse: Decodable {
    let data: FieldTripTemplate
}

struct FieldTripChallengesCatalogResponse: Decodable {
    let data: [FieldTripChallenge]
}

struct FieldTripChallengeDetailResponse: Decodable {
    let data: FieldTripChallenge
}

struct FieldTripRecentPublicationsResponse: Decodable {
    let data: [FieldTripRecentPublication]
}

struct FieldTripCommunityPublicationsResponse: Decodable {
    let data: [FieldTripRecentPublication]
}

struct FieldTripChallengePublicationsResponse: Decodable {
    let data: [FieldTripChallengeEntry]
}

enum FieldTripCommunityMode: String, CaseIterable, Identifiable {
    case smart
    case following
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart:
            "For You"
        case .following:
            "Following"
        case .recent:
            "Recent"
        }
    }
}

struct FieldTripProgressUpdatesResponse: Decodable {
    let data: [FieldTripProgressUpdate]
    let challengeUpdates: [FieldTripChallengeProgressUpdate]
    let firstFieldTripAchievement: FirstFieldTripAchievementProgress?
    let firstFieldTripAchievementNewlyUnlocked: Bool

    private enum CodingKeys: String, CodingKey {
        case data
        case challengeUpdates
        case firstFieldTripAchievement
        case firstFieldTripAchievementNewlyUnlocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([FieldTripProgressUpdate].self, forKey: .data) ?? []
        challengeUpdates = try container.decodeIfPresent([FieldTripChallengeProgressUpdate].self, forKey: .challengeUpdates) ?? []
        firstFieldTripAchievement = try container.decodeIfPresent(
            FirstFieldTripAchievementProgress.self,
            forKey: .firstFieldTripAchievement
        )
        firstFieldTripAchievementNewlyUnlocked = try container.decodeIfPresent(
            Bool.self,
            forKey: .firstFieldTripAchievementNewlyUnlocked
        ) ?? false
    }
}

struct FieldTripPreferredGoal: Codable, Equatable, Sendable {
    let userFieldTripId: String
    let itemId: String
}

struct FieldTripScanContributionsResponse: Decodable {
    let data: [FieldTripScanContribution]
}

struct FieldTripScanContribution: Decodable, Identifiable, Equatable, Sendable {
    enum SourceKind: String, Decodable, Sendable {
        case standardOuting = "standard_outing"
        case event
    }

    let sourceKind: SourceKind
    let sourceId: String
    let userFieldTripId: String?
    let participationId: String?
    let templateId: String
    let challengeId: String?
    let title: String
    let slug: String
    let itemId: String
    let prompt: String
    let levelNumber: Int
    let levelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool
    let artworkPrompt: String
    let artworkTemplateSlug: String?
    let destinationKind: String
    let destinationTemplateId: String?
    let destinationChecklistItemId: String?
    let destinationChallengeId: String?

    var id: String { "\(sourceKind.rawValue):\(sourceId)" }

    var destination: CaptureGoalDestination? {
        switch sourceKind {
        case .standardOuting:
            guard let destinationTemplateId, let destinationChecklistItemId else { return nil }
            return .fieldTrip(
                templateId: destinationTemplateId,
                checklistItemId: destinationChecklistItemId
            )
        case .event:
            guard let destinationChallengeId else { return nil }
            return .fieldTripChallenge(challengeId: destinationChallengeId)
        }
    }
}

struct FieldTripProgressResult: Equatable {
    let fieldTripUpdates: [FieldTripProgressUpdate]
    let challengeUpdates: [FieldTripChallengeProgressUpdate]
    let firstFieldTripAchievement: FirstFieldTripAchievementProgress?
    let firstFieldTripAchievementNewlyUnlocked: Bool

    init(
        fieldTripUpdates: [FieldTripProgressUpdate],
        challengeUpdates: [FieldTripChallengeProgressUpdate],
        firstFieldTripAchievement: FirstFieldTripAchievementProgress? = nil,
        firstFieldTripAchievementNewlyUnlocked: Bool = false
    ) {
        self.fieldTripUpdates = fieldTripUpdates
        self.challengeUpdates = challengeUpdates
        self.firstFieldTripAchievement = firstFieldTripAchievement
        self.firstFieldTripAchievementNewlyUnlocked = firstFieldTripAchievementNewlyUnlocked
    }
}

struct FirstFieldTripAwardResponse: Decodable {
    let data: FirstFieldTripAchievementProgress?
}

struct FirstFieldTripAchievementProgress: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case standardOuting = "standard_outing"
        case seasonalChallenge = "seasonal_challenge"
    }

    let kind: Kind
    let completedAt: String
    let templateSlug: String?
    let challengeId: String?

    var completionDate: Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: completedAt)
            ?? DateUtilities.iso8601Formatter.date(from: completedAt)
    }

    var destination: CaptureGoalDestination? {
        switch kind {
        case .standardOuting:
            guard let templateSlug = templateSlug?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !templateSlug.isEmpty else { return nil }
            return .fieldTripTemplate(slug: templateSlug)
        case .seasonalChallenge:
            guard let challengeId = challengeId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !challengeId.isEmpty else { return nil }
            return .fieldTripChallenge(challengeId: challengeId)
        }
    }

    var awardPayload: AwardPayload? {
        guard let completionDate, let destination else { return nil }
        return AwardPayload(
            type: .firstFieldTrip,
            currentCount: 1,
            lastInteractionDate: completionDate,
            unlockedAt: completionDate,
            destination: destination
        )
    }
}

enum FirstFieldTripAchievementProgressStore {
    static func load(
        accountId: String,
        userDefaults: UserDefaults = .standard
    ) -> FirstFieldTripAchievementProgress? {
        guard let data = userDefaults.data(forKey: key(accountId: accountId)),
              let progress = try? JSONDecoder().decode(FirstFieldTripAchievementProgress.self, from: data),
              progress.awardPayload != nil else {
            return nil
        }
        return progress
    }

    static func save(
        _ progress: FirstFieldTripAchievementProgress,
        accountId: String,
        userDefaults: UserDefaults = .standard
    ) {
        guard progress.awardPayload != nil,
              let data = try? JSONEncoder().encode(progress) else { return }
        userDefaults.set(data, forKey: key(accountId: accountId))
    }

    static func key(accountId: String) -> String {
        UserDefaultsKeys.firstFieldTripAchievementProgressPrefix
            + accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Array where Element == AwardPayload {
    func mergingFirstFieldTripAchievement(
        _ progress: FirstFieldTripAchievementProgress?
    ) -> [AwardPayload] {
        guard let completedAward = progress?.awardPayload else { return self }

        var merged = self
        if let index = merged.firstIndex(where: { $0.type == .firstFieldTrip }) {
            merged[index] = completedAward
        } else {
            merged.append(completedAward)
        }
        return merged
    }
}

struct FieldTripProfileSummariesResponse: Decodable {
    let data: FieldTripProfileSummaries
}

struct FieldTripSetPinnedPublicationsResponse: Decodable {
    let data: FieldTripProfileSummaries
}

struct FieldTripPublicationDetailResponse: Decodable {
    let data: FieldTripPublicationDetail
}

struct FieldTripChallengeEntryDetailResponse: Decodable {
    let data: FieldTripChallengeEntryDetail
}

struct FieldTripCommentsResponse: Decodable {
    let data: [ExploreComment]
}

struct FieldTripCreateCommentResponse: Decodable {
    let comment: ExploreComment
    let commentCount: Int
}

enum FieldTripDifficulty: String, CaseIterable, Identifiable {
    case starter
    case easy
    case moderate
    case hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    init?(apiValue: String) {
        self.init(
            rawValue: apiValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        )
    }
}

enum FieldTripDifficultyFilter: String, CaseIterable, Identifiable {
    case all
    case starter
    case easy
    case moderate
    case hard

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var difficulty: FieldTripDifficulty? {
        guard self != .all else { return nil }
        return FieldTripDifficulty(rawValue: rawValue)
    }
}

enum FieldTripCatalogState: String, CaseIterable, Identifiable {
    case completed
    case inProgress
    case incomplete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .completed:
            "Completed"
        case .inProgress:
            "In progress"
        case .incomplete:
            "Incomplete"
        }
    }
}

enum FieldTripStateFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case inProgress
    case incomplete

    var id: String { rawValue }

    var title: String {
        state?.title ?? "All statuses"
    }

    var state: FieldTripCatalogState? {
        guard self != .all else { return nil }
        return FieldTripCatalogState(rawValue: rawValue)
    }
}

struct FieldTripCatalogFilters: Equatable {
    var difficulty: FieldTripDifficultyFilter = .all
    var state: FieldTripStateFilter = .all

    var activeFilterCount: Int {
        (difficulty == .all ? 0 : 1) + (state == .all ? 0 : 1)
    }

    var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    mutating func reset() {
        difficulty = .all
        state = .all
    }
}

struct FieldTripLikeResponse: Decodable, Equatable {
    let publicationId: String
    let viewerHasLiked: Bool
    let likeCount: Int
    let commentCount: Int?
}

struct FieldTripChallengeEntryLikeResponse: Decodable, Equatable {
    let entryId: String
    let viewerHasLiked: Bool
    let likeCount: Int
    let commentCount: Int?
}

struct FieldTripChallengeHashtagsResponse: Decodable {
    let data: [String]
}

struct FieldTripTemplate: Decodable, Identifiable, Equatable, Sendable {
    let templateId: String
    let slug: String
    let title: String
    let subtitle: String?
    let description: String?
    let coverImageUrl: String?
    let estimatedDurationMinutes: Int?
    let guideWhereToLook: String?
    let guideWhyItMatters: String?
    let guideSafetyEthics: String?
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let difficulty: String
    let isProOnly: Bool
    let isRotatingFree: Bool
    let viewerHasAccess: Bool
    let accessKind: String
    let activeProgress: FieldTripProgress?
    let stoppedProgress: FieldTripProgress?
    let levels: [FieldTripLevel]

    var id: String { templateId }
    var resolvedDifficulty: FieldTripDifficulty? {
        FieldTripDifficulty(apiValue: difficulty)
    }

    var catalogState: FieldTripCatalogState {
        guard let viewerProgress else { return .incomplete }
        return viewerProgress.isComplete ? .completed : .inProgress
    }

    var viewerProgress: FieldTripProgress? {
        activeProgress ?? stoppedProgress
    }

    var isStopped: Bool {
        stoppedProgress != nil
    }

    var difficultyTitle: String {
        if let resolvedDifficulty {
            return resolvedDifficulty.title
        }

        let normalized = difficulty
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
        return normalized.isEmpty ? "Unknown" : normalized.capitalized
    }
}

extension Array where Element == FieldTripTemplate {
    func filtering(by difficulty: FieldTripDifficulty?) -> [FieldTripTemplate] {
        guard let difficulty else { return self }
        return filter { $0.resolvedDifficulty == difficulty }
    }

    func filtering(by filters: FieldTripCatalogFilters) -> [FieldTripTemplate] {
        filter { template in
            let matchesDifficulty = filters.difficulty.difficulty.map {
                template.resolvedDifficulty == $0
            } ?? true
            let matchesState = filters.state.state.map {
                template.catalogState == $0
            } ?? true
            return matchesDifficulty && matchesState
        }
    }
}

struct FieldTripLevel: Decodable, Identifiable, Equatable, Sendable {
    let levelId: String
    let levelNumber: Int
    let title: String
    let description: String?
    let items: [FieldTripChecklistItem]

    var id: String { levelId }
}

struct FieldTripChecklistItem: Decodable, Identifiable, Equatable, Sendable {
    let itemId: String
    let prompt: String
    let matchType: String
    let guideTip: String?
    let guide: FieldTripChecklistItemGuide?
    let isCompleted: Bool
    let completedAt: String?
    let completedCommonName: String?
    let completedScientificName: String?
    let completedScanId: String?

    var id: String { itemId }

    var hasGuide: Bool {
        guide?.hasContent == true || guideTip?.fieldTripNonBlank != nil
    }

    var guidePreview: String? {
        guide?.preview ?? guideTip?.fieldTripNonBlank
    }
}

struct FieldTripChecklistItemGuide: Decodable, Equatable, Sendable {
    let whereToLook: String?
    let bestConditions: String?
    let whatToNotice: String?
    let scanSafely: String?

    var hasContent: Bool {
        preview != nil
    }

    var preview: String? {
        whereToLook?.fieldTripNonBlank
            ?? bestConditions?.fieldTripNonBlank
            ?? whatToNotice?.fieldTripNonBlank
            ?? scanSafely?.fieldTripNonBlank
    }
}

private extension String {
    var fieldTripNonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct FieldTripProgress: Decodable, Equatable, Sendable {
    let userFieldTripId: String
    let startedAt: String
    let currentLevelNumber: Int
    let completedAt: String?
    let isProfileVisible: Bool
    let completedCount: Int
    let targetCount: Int
    let publicationId: String?
    let publishedAt: String?
    let stoppedAt: String?

    var isComplete: Bool { completedAt != nil }
    var isPublished: Bool { publicationId != nil }
    var fractionComplete: Double {
        guard targetCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(targetCount)))
    }
}

enum FieldTripDetailPrimaryAction: Equatable {
    case unlock
    case start
    case resume
    case publish
    case scan
}

enum FieldTripDetailLifecyclePresentation {
    static func primaryAction(
        for template: FieldTripTemplate,
        sharingEnabled: Bool = FieldTripSharingAvailability.isEnabled
    ) -> FieldTripDetailPrimaryAction? {
        guard template.viewerHasAccess else { return .unlock }
        if template.isStopped { return .resume }
        guard let progress = template.viewerProgress else { return .start }
        guard !progress.isComplete else {
            return sharingEnabled ? .publish : nil
        }
        return .scan
    }

    static func canStop(_ template: FieldTripTemplate) -> Bool {
        guard let progress = template.activeProgress else { return false }
        return !progress.isComplete
    }

    static func canReset(_ template: FieldTripTemplate) -> Bool {
        guard let progress = template.viewerProgress else { return false }
        return !progress.isComplete && progress.publicationId == nil
    }

    static func showsOptionsMenu(_ template: FieldTripTemplate) -> Bool {
        canStop(template) || canReset(template)
    }
}

struct FieldTripProgressUpdate: Decodable, Identifiable, Equatable {
    let userFieldTripId: String
    let templateId: String
    let slug: String
    let title: String
    let currentLevelNumber: Int
    let currentLevelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool
    let creditedLevelNumber: Int?
    let creditedLevelTitle: String?
    let creditedCompletedCount: Int?
    let creditedTargetCount: Int?
    let newlyCompletedItems: [FieldTripProgressCompletedItem]
    let removedItemIds: [String]?

    var id: String { userFieldTripId }

    var toastCompletedCount: Int { creditedCompletedCount ?? completedCount }
    var toastTargetCount: Int { creditedTargetCount ?? targetCount }
}

struct FieldTripProgressCompletedItem: Decodable, Identifiable, Equatable {
    let itemId: String
    let prompt: String
    let commonName: String?
    let scientificName: String?
    let completedAt: String?

    var id: String { itemId }
}

struct FieldTripChallengeProgressUpdate: Decodable, Identifiable, Equatable {
    let participationId: String
    let challengeId: String
    let slug: String
    let title: String
    let currentLevelNumber: Int
    let currentLevelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool
    let badgeAwardedAt: String?
    let suggestedHashtags: [String]
    let creditedLevelNumber: Int?
    let creditedLevelTitle: String?
    let creditedCompletedCount: Int?
    let creditedTargetCount: Int?
    let newlyCompletedItems: [FieldTripProgressCompletedItem]
    let removedItemIds: [String]?

    var id: String { participationId }

    var toastCompletedCount: Int { creditedCompletedCount ?? completedCount }
    var toastTargetCount: Int { creditedTargetCount ?? targetCount }
}

struct FieldTripProfileSummaries: Decodable, Equatable {
    let active: [FieldTripProfileActiveSummary]
    let pinned: [FieldTripProfilePublishedSummary]
    let published: [FieldTripProfilePublishedSummary]
    let challengeBadges: [FieldTripChallengeBadge]

    var isEmpty: Bool {
        active.isEmpty && pinned.isEmpty && published.isEmpty && challengeBadges.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case active
        case pinned
        case published
        case challengeBadges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        active = try container.decodeIfPresent([FieldTripProfileActiveSummary].self, forKey: .active) ?? []
        pinned = try container.decodeIfPresent([FieldTripProfilePublishedSummary].self, forKey: .pinned) ?? []
        published = try container.decodeIfPresent([FieldTripProfilePublishedSummary].self, forKey: .published) ?? []
        challengeBadges = try container.decodeIfPresent([FieldTripChallengeBadge].self, forKey: .challengeBadges) ?? []
    }
}

struct FieldTripChallengeBadge: Decodable, Identifiable, Equatable {
    let badgeId: String
    let challengeId: String
    let badgeKey: String
    let title: String
    let awardedAt: String
    let challengeSlug: String
    let challengeTitle: String
    let coverImageUrl: String?
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]

    var id: String { badgeId }
}

struct FieldTripProfileActiveSummary: Decodable, Identifiable, Equatable {
    let userFieldTripId: String
    let templateId: String
    let slug: String
    let title: String
    let startedAt: String?
    let currentLevelNumber: Int
    let currentLevelTitle: String?
    let completedCount: Int
    let targetCount: Int
    let isComplete: Bool

    var id: String { userFieldTripId }
}

struct FieldTripProfilePublishedSummary: Decodable, Identifiable, Equatable {
    let publicationId: String
    let title: String
    let description: String?
    let publishedAt: String
    let likeCount: Int
    let commentCount: Int
    let slug: String
    let templateTitle: String
    let coverImageUrl: String?
    let itemCount: Int
    let viewerHasLiked: Bool
    let isPinned: Bool
    let pinPosition: Int?

    var id: String { publicationId }

    private enum CodingKeys: String, CodingKey {
        case publicationId
        case title
        case description
        case publishedAt
        case likeCount
        case commentCount
        case slug
        case templateTitle
        case coverImageUrl
        case itemCount
        case viewerHasLiked
        case isPinned
        case pinPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicationId = try container.decode(String.self, forKey: .publicationId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        slug = try container.decode(String.self, forKey: .slug)
        templateTitle = try container.decode(String.self, forKey: .templateTitle)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        viewerHasLiked = try container.decode(Bool.self, forKey: .viewerHasLiked)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinPosition = try container.decodeIfPresent(Int.self, forKey: .pinPosition)
    }
}

struct FieldTripRecentPublication: Decodable, Identifiable, Equatable {
    let publicationId: String
    let templateId: String
    let title: String
    let description: String?
    let publishedAt: String
    let likeCount: Int
    let commentCount: Int
    let slug: String
    let templateTitle: String
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let coverImageUrl: String?
    let itemCount: Int
    let viewerHasLiked: Bool
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    let isPinned: Bool
    let pinPosition: Int?
    let rankBucket: Int?
    let communityReason: String?
    let viewerIsFollowingAuthor: Bool

    var id: String { publicationId }

    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    var communityReasonLabel: String? {
        if viewerIsFollowingAuthor {
            return "Following"
        }

        switch communityReason {
        case "near_you":
            return "Near you"
        case "global":
            return "Global"
        case "new":
            return "New"
        case "following":
            return "Following"
        default:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case publicationId
        case templateId
        case title
        case description
        case publishedAt
        case likeCount
        case commentCount
        case slug
        case templateTitle
        case regionTags
        case seasonTags
        case habitatTags
        case coverImageUrl
        case itemCount
        case viewerHasLiked
        case authorUserId
        case authorName
        case authorUsername
        case authorAvatarUrl
        case isPinned
        case pinPosition
        case rankBucket
        case communityReason
        case viewerIsFollowingAuthor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicationId = try container.decode(String.self, forKey: .publicationId)
        templateId = try container.decode(String.self, forKey: .templateId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        publishedAt = try container.decode(String.self, forKey: .publishedAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        slug = try container.decode(String.self, forKey: .slug)
        templateTitle = try container.decode(String.self, forKey: .templateTitle)
        regionTags = try container.decodeIfPresent([String].self, forKey: .regionTags) ?? []
        seasonTags = try container.decodeIfPresent([String].self, forKey: .seasonTags) ?? []
        habitatTags = try container.decodeIfPresent([String].self, forKey: .habitatTags) ?? []
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        itemCount = try container.decode(Int.self, forKey: .itemCount)
        viewerHasLiked = try container.decode(Bool.self, forKey: .viewerHasLiked)
        authorUserId = try container.decode(String.self, forKey: .authorUserId)
        authorName = try container.decode(String.self, forKey: .authorName)
        authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername)
        authorAvatarUrl = try container.decodeIfPresent(String.self, forKey: .authorAvatarUrl)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinPosition = try container.decodeIfPresent(Int.self, forKey: .pinPosition)
        rankBucket = try container.decodeIfPresent(Int.self, forKey: .rankBucket)
        communityReason = try container.decodeIfPresent(String.self, forKey: .communityReason)
        viewerIsFollowingAuthor = try container.decodeIfPresent(Bool.self, forKey: .viewerIsFollowingAuthor) ?? false
    }
}

struct FieldTripChallenge: Decodable, Identifiable, Equatable {
    let challengeId: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let slug: String
    let title: String
    let subtitle: String?
    let description: String?
    let coverImageUrl: String?
    let startsAt: String
    let endsAt: String
    let status: String
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let suggestedHashtags: [String]
    let isProOnly: Bool
    let isTemporarilyFree: Bool
    let viewerHasAccess: Bool
    let accessKind: String
    let participantCount: Int
    let completionCount: Int
    let publishedEntryCount: Int
    let viewerParticipation: FieldTripChallengeParticipation?
    let template: FieldTripTemplate?
    let entries: [FieldTripChallengeEntry]

    var id: String { challengeId }
    var isLive: Bool { status == "live" }
    var isUpcoming: Bool { status == "upcoming" }
    var isEnded: Bool { status == "ended" }

    private enum CodingKeys: String, CodingKey {
        case challengeId
        case templateId
        case templateSlug
        case templateTitle
        case slug
        case title
        case subtitle
        case description
        case coverImageUrl
        case startsAt
        case endsAt
        case status
        case regionTags
        case seasonTags
        case habitatTags
        case suggestedHashtags
        case isProOnly
        case isTemporarilyFree
        case viewerHasAccess
        case accessKind
        case participantCount
        case completionCount
        case publishedEntryCount
        case viewerParticipation
        case template
        case entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        challengeId = try container.decode(String.self, forKey: .challengeId)
        templateId = try container.decode(String.self, forKey: .templateId)
        templateSlug = try container.decodeIfPresent(String.self, forKey: .templateSlug) ?? ""
        templateTitle = try container.decodeIfPresent(String.self, forKey: .templateTitle) ?? ""
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverImageUrl = try container.decodeIfPresent(String.self, forKey: .coverImageUrl)
        startsAt = try container.decode(String.self, forKey: .startsAt)
        endsAt = try container.decode(String.self, forKey: .endsAt)
        status = try container.decode(String.self, forKey: .status)
        regionTags = try container.decodeIfPresent([String].self, forKey: .regionTags) ?? []
        seasonTags = try container.decodeIfPresent([String].self, forKey: .seasonTags) ?? []
        habitatTags = try container.decodeIfPresent([String].self, forKey: .habitatTags) ?? []
        suggestedHashtags = try container.decodeIfPresent([String].self, forKey: .suggestedHashtags) ?? []
        isProOnly = try container.decodeIfPresent(Bool.self, forKey: .isProOnly) ?? false
        isTemporarilyFree = try container.decodeIfPresent(Bool.self, forKey: .isTemporarilyFree) ?? false
        viewerHasAccess = try container.decodeIfPresent(Bool.self, forKey: .viewerHasAccess) ?? true
        accessKind = try container.decodeIfPresent(String.self, forKey: .accessKind) ?? "free"
        participantCount = try container.decodeIfPresent(Int.self, forKey: .participantCount) ?? 0
        completionCount = try container.decodeIfPresent(Int.self, forKey: .completionCount) ?? 0
        publishedEntryCount = try container.decodeIfPresent(Int.self, forKey: .publishedEntryCount) ?? 0
        viewerParticipation = try container.decodeIfPresent(FieldTripChallengeParticipation.self, forKey: .viewerParticipation)
        template = try container.decodeIfPresent(FieldTripTemplate.self, forKey: .template)
        entries = try container.decodeIfPresent([FieldTripChallengeEntry].self, forKey: .entries) ?? []
    }
}

struct FieldTripChallengeParticipation: Decodable, Equatable {
    let participationId: String
    let userFieldTripId: String
    let joinedAt: String
    let currentLevelNumber: Int
    let completedAt: String?
    let badgeAwardedAt: String?
    let completedCount: Int
    let targetCount: Int

    var isComplete: Bool { completedAt != nil }
    var fractionComplete: Double {
        guard targetCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(targetCount)))
    }
}

struct FieldTripChallengeEntry: Decodable, Identifiable, Equatable {
    let entryId: String
    let challengeId: String
    let challengeSlug: String
    let challengeTitle: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let title: String
    let description: String?
    let publishedAt: String
    let likeCount: Int
    let commentCount: Int
    let regionTags: [String]
    let seasonTags: [String]
    let habitatTags: [String]
    let coverImageUrl: String?
    let itemCount: Int
    let viewerHasLiked: Bool
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?

    var id: String { entryId }

    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
}

struct FieldTripChallengeEntryDetail: Decodable, Identifiable, Equatable {
    let entryId: String
    let participationId: String
    let challengeId: String
    let challengeSlug: String
    let challengeTitle: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let title: String
    let description: String?
    let publishedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let isOwnedByViewer: Bool
    let items: [FieldTripChallengeEntryItem]

    var id: String { entryId }

    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
}

struct FieldTripChallengeEntryItem: Decodable, Identifiable, Equatable {
    let entryItemId: String
    let itemId: String
    let prompt: String
    let commonName: String?
    let scientificName: String?
    let heroImageUrl: String?
    let referenceImageUrl: String?
    let taxonomy: [String: String?]?

    var id: String { entryItemId }

    var displayName: String {
        commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? scientificName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? prompt
    }
}

struct FieldTripPublicationDetail: Decodable, Identifiable, Equatable {
    let publicationId: String
    let userFieldTripId: String
    let templateId: String
    let templateSlug: String
    let templateTitle: String
    let title: String
    let description: String?
    let aiSummary: String?
    let publishedAt: String
    let authorUserId: String
    let authorName: String
    let authorUsername: String?
    let authorAvatarUrl: String?
    var likeCount: Int
    var commentCount: Int
    var viewerHasLiked: Bool
    let items: [FieldTripPublicationItem]

    var id: String { publicationId }

    var publicAuthorDisplayName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
}

struct FieldTripPublicationItem: Decodable, Identifiable, Equatable {
    let publicationItemId: String
    let itemId: String
    let prompt: String
    let commonName: String?
    let scientificName: String?
    let heroImageUrl: String?
    let referenceImageUrl: String?
    let taxonomy: [String: String?]?

    var id: String { publicationItemId }

    var displayName: String {
        commonName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? scientificName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? prompt
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
