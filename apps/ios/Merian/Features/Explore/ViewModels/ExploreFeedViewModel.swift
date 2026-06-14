import Foundation
import Observation
import Supabase
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
        feedPosts = posts
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

        feedPosts.append(contentsOf: uniquePosts)
        for post in uniquePosts {
            supplementalPostsById.removeValue(forKey: post.id)
        }
        changeVersion &+= 1
    }

    func upsert(_ post: ExplorePost, includeInFeed: Bool = false) {
        if let index = feedPosts.firstIndex(where: { $0.id == post.id }) {
            feedPosts[index] = post
            supplementalPostsById.removeValue(forKey: post.id)
        } else if includeInFeed {
            feedPosts.append(post)
            supplementalPostsById.removeValue(forKey: post.id)
        } else {
            supplementalPostsById[post.id] = post
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

@MainActor
@Observable
final class ExploreFeedViewModel {
    @ObservationIgnored private var appSettings: AppSettings

    init(appSettings: AppSettings? = nil) {
        self.appSettings = appSettings ?? AppSettings.shared
    }

    let store = ExplorePostStore()
    var activeFilter: ExploreFeedFilter = .recent
    var isLoadingInitialFeed = false
    var isLoadingMore = false
    var errorMessage: String?
    var toastMessage: String?
    var unreadNotificationCount = 0
    var preferredSpeciesNamesByScientificName: [String: String] = [:]

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
    @ObservationIgnored var isRefreshingUnreadNotificationCount = false
    @ObservationIgnored var unreadNotificationsChannel: RealtimeChannelV2?
    @ObservationIgnored var unreadNotificationListenerTask: Task<Void, Never>?
    @ObservationIgnored var activeFeedRequestId = UUID()
    @ObservationIgnored var currentInitialFeedRequestId: UUID?
    @ObservationIgnored var currentLoadMoreRequestId: UUID?
    @ObservationIgnored var nearbyLocationSnapshot: ExploreNearbyLocationSnapshot?

    func bindSettings(_ appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    func markRecentFeedSeen(latestSharedAt: String?) {
        guard activeFilter == .recent else { return }
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

        let refreshedNames = SpeciesPreferredNameRepository.preferredNames(
            for: Array(normalizedNames),
            modelContext: modelContext
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
        resolvedSpeciesCommonName(
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
