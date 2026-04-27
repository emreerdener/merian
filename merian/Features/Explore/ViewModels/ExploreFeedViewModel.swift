import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ExploreFeedViewModel {
    var posts: [ExplorePost] = []
    var isLoadingInitialFeed = false
    var isLoadingMore = false
    var errorMessage: String?
    var toastMessage: String?

    var isCommentsSheetPresented = false
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
    @ObservationIgnored var feedOffset = 0
    @ObservationIgnored var hasLoadedFeedOnce = false
    @ObservationIgnored var hasReachedEndOfFeed = false
    @ObservationIgnored var activeCommentsRequestId = UUID()
    @ObservationIgnored var likeRequestsInFlight = Set<String>()
}
