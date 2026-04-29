import Foundation
import Observation
import Supabase
import SwiftUI

@MainActor
@Observable
final class ExploreFeedViewModel {
    var posts: [ExplorePost] = []
    var isLoadingInitialFeed = false
    var isLoadingMore = false
    var errorMessage: String?
    var toastMessage: String?
    var unreadNotificationCount = 0

    var isCommentsSheetPresented = false
    var isNotificationsSheetPresented = false
    var activeCommentsPostId: String?
    var comments: [ExploreComment] = []
    var isCommentsLoading = false
    var isSubmittingComment = false
    var commentDraft = ""
    var commentErrorMessage: String?

    var activeCommentsPost: ExplorePost? {
        guard let activeCommentsPostId else { return nil }
        return posts.first(where: { $0.id == activeCommentsPostId })
    }

    @ObservationIgnored let feedPageSize = 20
    @ObservationIgnored let commentsPageSize = 100
    @ObservationIgnored var nextFeedCursorSharedAt: String?
    @ObservationIgnored var nextFeedCursorPostId: String?
    @ObservationIgnored var hasLoadedFeedOnce = false
    @ObservationIgnored var hasReachedEndOfFeed = false
    @ObservationIgnored var activeCommentsRequestId = UUID()
    @ObservationIgnored var likeRequestsInFlight = Set<String>()
    @ObservationIgnored var isRefreshingUnreadNotificationCount = false
    @ObservationIgnored var unreadNotificationsChannel: RealtimeChannelV2?
    @ObservationIgnored var unreadNotificationListenerTask: Task<Void, Never>?
    @ObservationIgnored var mediaReloadGeneration: UInt64 = 0
}
