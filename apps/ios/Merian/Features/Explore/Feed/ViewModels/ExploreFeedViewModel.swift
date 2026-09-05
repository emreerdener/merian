import Foundation
import Observation
import SwiftData
import SwiftUI

struct ExploreNearbyLocationSnapshot: Equatable {
    let latitude: Double
    let longitude: Double
}

struct ExploreCommentCursor {
    let createdAt: String
    let commentId: String
}

enum ExploreFeedItem: Identifiable {
    case observation(ExplorePost)
    case fieldTrip(FieldTripRecentPublication)

    var id: String {
        switch self {
        case .observation(let post):
            "observation:\(post.id)"
        case .fieldTrip(let publication):
            "field-trip:\(publication.publicationId)"
        }
    }

    var publishedAt: String {
        switch self {
        case .observation(let post):
            post.sharedAt
        case .fieldTrip(let publication):
            publication.publishedAt
        }
    }
}

struct ExploreReplyThreadRenderState: Equatable {
    var replies: [ExploreComment] = []
    var isExpanded = false
    var isLoading = false
    var isLoadingPreview = false
    var isLoadingMore = false
    var didFail = false
    var hasLoadedPreview = false
    var hasLoadedReplies = false
    var hasReachedEnd = false
}

@MainActor
@Observable
final class ExplorePostStore {
    private(set) var feedPosts: [ExplorePost] = []
    private(set) var supplementalPostsById: [String: ExplorePost] = [:]
    private(set) var mediaReloadGeneration: UInt64 = 0
    private(set) var changeVersion: UInt64 = 0

    var allPosts: [ExplorePost] {
        var seenIds = Set(feedPosts.map(\.id))
        var combinedPosts = feedPosts

        for post in supplementalPostsById.values where seenIds.insert(post.id).inserted {
            combinedPosts.append(post)
        }

        return combinedPosts
    }

    func post(id: String) -> ExplorePost? {
        feedPosts.first(where: { $0.id == id }) ?? supplementalPostsById[id]
    }

    func containsFeedPost(id: String) -> Bool {
        feedPosts.contains(where: { $0.id == id })
    }

    func setFeedPosts(_ posts: [ExplorePost]) {
        let existingPostsById = Dictionary(uniqueKeysWithValues: allPosts.map { ($0.id, $0) })
        feedPosts = posts.map { post in
            post.mergingExistingMedia(from: existingPostsById[post.id])
        }
        for post in posts {
            supplementalPostsById.removeValue(forKey: post.id)
        }
        mediaReloadGeneration &+= 1
        changeVersion &+= 1
    }

    func appendUniqueFeedPosts(_ posts: [ExplorePost]) {
        guard !posts.isEmpty else { return }

        let existingIds = Set(feedPosts.map(\.id))
        let uniquePosts = posts.filter { existingIds.contains($0.id) == false }
        guard !uniquePosts.isEmpty else { return }

        feedPosts.append(contentsOf: uniquePosts.map { post in
            post.mergingExistingMedia(from: supplementalPostsById[post.id])
        })
        for post in uniquePosts {
            supplementalPostsById.removeValue(forKey: post.id)
        }
        changeVersion &+= 1
    }

    func upsert(_ post: ExplorePost, includeInFeed: Bool = false) {
        if let index = feedPosts.firstIndex(where: { $0.id == post.id }) {
            feedPosts[index] = post.mergingExistingMedia(from: feedPosts[index])
            supplementalPostsById.removeValue(forKey: post.id)
        } else if includeInFeed {
            let existingPost = supplementalPostsById[post.id]
            feedPosts.append(post.mergingExistingMedia(from: existingPost))
            supplementalPostsById.removeValue(forKey: post.id)
        } else {
            supplementalPostsById[post.id] = post.mergingExistingMedia(from: supplementalPostsById[post.id])
        }

        changeVersion &+= 1
    }

    func removePost(id: String) {
        let originalFeedCount = feedPosts.count
        feedPosts.removeAll { $0.id == id }
        let removedSupplemental = supplementalPostsById.removeValue(forKey: id) != nil

        guard feedPosts.count != originalFeedCount || removedSupplemental else { return }
        changeVersion &+= 1
    }

    func removePosts(byAuthorUserId authorUserId: String) {
        let originalFeedCount = feedPosts.count
        feedPosts.removeAll { $0.authorUserId == authorUserId }

        let supplementalIdsToRemove = supplementalPostsById.values
            .filter { $0.authorUserId == authorUserId }
            .map(\.id)
        for id in supplementalIdsToRemove {
            supplementalPostsById.removeValue(forKey: id)
        }

        guard feedPosts.count != originalFeedCount || supplementalIdsToRemove.isEmpty == false else { return }
        changeVersion &+= 1
    }

    func applyLikeState(postId: String, likeCount: Int, viewerHasLiked: Bool) {
        mutate(postId: postId) { post in
            post.likeCount = max(0, likeCount)
            post.viewerHasLiked = viewerHasLiked
        }
    }

    func updateCommentCount(postId: String, commentCount: Int) {
        mutate(postId: postId) { post in
            post.commentCount = max(0, commentCount)
        }
    }

    func toggleLikeOptimistically(postId: String) -> (previousLikedState: Bool, previousLikeCount: Int)? {
        guard let existingPost = post(id: postId) else { return nil }
        let previousLikedState = existingPost.viewerHasLiked
        let previousLikeCount = existingPost.likeCount

        mutate(postId: postId) { post in
            post.viewerHasLiked.toggle()
            post.likeCount = max(0, previousLikeCount + (post.viewerHasLiked ? 1 : -1))
        }

        return (previousLikedState, previousLikeCount)
    }

    private func mutate(postId: String, _ transform: (inout ExplorePost) -> Void) {
        if let index = feedPosts.firstIndex(where: { $0.id == postId }) {
            var post = feedPosts[index]
            transform(&post)
            feedPosts[index] = post
            supplementalPostsById.removeValue(forKey: postId)
            changeVersion &+= 1
            return
        }

        guard var post = supplementalPostsById[postId] else { return }
        transform(&post)
        supplementalPostsById[postId] = post
        changeVersion &+= 1
    }
}

private extension ExplorePost {
    func mergingExistingMedia(from existingPost: ExplorePost?) -> ExplorePost {
        guard mediaItems?.isEmpty != false,
              let existingMediaItems = existingPost?.mediaItems,
              !existingMediaItems.isEmpty else {
            return self
        }

        var mergedPost = self
        mergedPost.mediaItems = existingMediaItems
        return mergedPost
    }
}

@MainActor
@Observable
final class ExploreFeedViewModel {
    @ObservationIgnored private var appSettings: AppSettings
    @ObservationIgnored let dependencies: Dependencies

    init(
        appSettings: AppSettings? = nil,
        dependencies: Dependencies = .live
    ) {
        self.appSettings = appSettings ?? AppSettings.shared
        self.dependencies = dependencies
    }

    let store = ExplorePostStore()
    var activeFilter: ExploreFeedFilter = .recent
    var advancedFilters = ExploreFeedAdvancedFilters()
    var isLoadingInitialFeed = false
    var isLoadingMore = false
    var errorMessage: String?
    var toastMessage: ToastPayload?
    var unreadNotificationCount = 0
    var preferredSpeciesNamesByScientificName: [String: String] = [:]
    var fieldTripPublications: [FieldTripRecentPublication] = []

    var isCommentsSheetPresented = false
    var isNotificationsSheetPresented = false
    var activeCommentsPostId: String?
    var comments: [ExploreComment] = []
    var isCommentsLoading = false
    var isLoadingMoreComments = false
    var isSubmittingComment = false
    var commentDraft = ""
    var composerResetToken = UUID()
    var commentErrorMessage: String?
    var replyingToComment: ExploreComment?
    var repliesByCommentId: [String: [ExploreComment]] = [:]
    var expandedReplyCommentIds: Set<String> = []
    var loadingReplyCommentIds: Set<String> = []
    var loadingReplyPreviewCommentIds: Set<String> = []
    var loadingMoreReplyCommentIds: Set<String> = []
    var failedReplyCommentIds: Set<String> = []
    var hasLoadedReplyPreviewByCommentId = Set<String>()
    var hasLoadedRepliesByCommentId = Set<String>()
    var hasReachedEndOfRepliesByCommentId = Set<String>()
    var replyThreadRenderStates: [String: ExploreReplyThreadRenderState] = [:]
    var replyStateVersion: UInt64 = 0

    var posts: [ExplorePost] {
        store.feedPosts
    }

    var feedItems: [ExploreFeedItem] {
        let observations = posts.map(ExploreFeedItem.observation)
        let fieldTrips = FeatureFlags.isEnabled(.fieldTrips)
            ? fieldTripPublications.map(ExploreFeedItem.fieldTrip)
            : []
        return (observations + fieldTrips).sorted { $0.publishedAt > $1.publishedAt }
    }

    var mediaReloadGeneration: UInt64 {
        store.mediaReloadGeneration
    }

    var activeCommentsPost: ExplorePost? {
        guard let activeCommentsPostId else { return nil }
        return store.post(id: activeCommentsPostId)
    }

    @ObservationIgnored let feedPageSize = 20
    @ObservationIgnored let commentsPageSize = 100
    @ObservationIgnored let repliesPageSize = 25
    @ObservationIgnored var nextFeedCursor = ExploreFeedCursor.empty
    @ObservationIgnored var hasLoadedFeedOnce = false
    @ObservationIgnored var hasReachedEndOfFeed = false
    @ObservationIgnored var nextCommentsCursorCreatedAt: String?
    @ObservationIgnored var nextCommentsCursorCommentId: String?
    @ObservationIgnored var hasLoadedCommentsOnce = false
    @ObservationIgnored var hasReachedEndOfComments = false
    @ObservationIgnored var replyCursorsByCommentId: [String: ExploreCommentCursor] = [:]
    @ObservationIgnored var pendingExpandedReplyParentCommentId: String?
    @ObservationIgnored var activeReplyTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var activeCommentsRequestId = UUID()
    @ObservationIgnored var likeRequestsInFlight = Set<String>()
    @ObservationIgnored var activeFeedRequestId = UUID()
    @ObservationIgnored var currentInitialFeedRequestId: UUID?
    @ObservationIgnored var currentLoadMoreRequestId: UUID?
    @ObservationIgnored var nearbyLocationSnapshot: ExploreNearbyLocationSnapshot?
    @ObservationIgnored var activeSharedSince: Date?

    var activeAdvancedFilterCount: Int {
        advancedFilters.activeFilterCount(for: activeFilter)
    }

    var hasActiveAdvancedFilters: Bool {
        advancedFilters.hasActiveFilters(for: activeFilter)
    }

    var hasStoredAdvancedFilters: Bool {
        advancedFilters.hasStoredSelections
    }

    var isCanonicalRecentFeed: Bool {
        activeFilter == .recent && !advancedFilters.hasObservationFilters
    }

    func bindSettings(_ appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    func markRecentFeedSeen(latestSharedAt: String?) {
        guard isCanonicalRecentFeed else { return }
        appSettings.hasUnseenExplorePost = false

        if let latestSharedAt {
            appSettings.lastSeenExplorePostSharedAt = latestSharedAt
        }
    }

    func post(id: String) -> ExplorePost? {
        store.post(id: id)
    }

    func refreshPreferredSpeciesNames(modelContext: ModelContext) {
        refreshPreferredSpeciesNames(
            for: store.allPosts.map(\.speciesScientificName),
            modelContext: modelContext
        )
    }

    func refreshPreferredSpeciesNames(
        for scientificNames: [String],
        modelContext: ModelContext
    ) {
        let normalizedNames = Set(
            scientificNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !normalizedNames.isEmpty else { return }

        let refreshedNames = dependencies.loadPreferredSpeciesNames(
            Array(normalizedNames),
            modelContext
        )

        var nextNames = preferredSpeciesNamesByScientificName
        for scientificName in normalizedNames {
            nextNames.removeValue(forKey: scientificName)
        }
        for (scientificName, preferredName) in refreshedNames {
            nextNames[scientificName] = preferredName
        }
        preferredSpeciesNamesByScientificName = nextNames
    }

    func resolvedSpeciesCommonName(for post: ExplorePost) -> String {
        if let petLabel = post.petIdentification?.label.trimmingCharacters(in: .whitespacesAndNewlines),
           !petLabel.isEmpty {
            return petLabel
        }
        return resolvedSpeciesCommonName(
            scientificName: post.speciesScientificName,
            fallbackCommonName: post.speciesCommonName
        )
    }

    func resolvedSpeciesCommonName(
        scientificName: String,
        fallbackCommonName: String
    ) -> String {
        let scientificName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preferredName = preferredSpeciesNamesByScientificName[scientificName]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preferredName.isEmpty {
            return preferredName
        }

        let fallbackName = fallbackCommonName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallbackName.isEmpty {
            return fallbackName.capitalized
        }

        return scientificName
    }

    var currentNearbyLatitude: Double? {
        nearbyLocationSnapshot?.latitude
    }

    var currentNearbyLongitude: Double? {
        nearbyLocationSnapshot?.longitude
    }

}
