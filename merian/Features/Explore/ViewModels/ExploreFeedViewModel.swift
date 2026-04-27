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

    @ObservationIgnored private let feedPageSize = 20
    @ObservationIgnored private let commentsPageSize = 100
    @ObservationIgnored private var feedOffset = 0
    @ObservationIgnored private var hasLoadedFeedOnce = false
    @ObservationIgnored private var hasReachedEndOfFeed = false
    @ObservationIgnored private var activeCommentsRequestId = UUID()
    @ObservationIgnored private var likeRequestsInFlight = Set<String>()

    func loadInitialFeed(force: Bool = false) async {
        guard !isLoadingInitialFeed else { return }
        guard force || !hasLoadedFeedOnce else { return }

        isLoadingInitialFeed = true
        if force {
            errorMessage = nil
        }

        defer { isLoadingInitialFeed = false }

        do {
            let freshPosts = try await MerianNetworkClient.shared.getExploreFeed(
                limit: feedPageSize,
                offset: 0
            )

            posts = freshPosts
            feedOffset = freshPosts.count
            hasLoadedFeedOnce = true
            hasReachedEndOfFeed = freshPosts.count < feedPageSize
            errorMessage = nil
            reconcileActiveCommentsPost()
        } catch is CancellationError {
            // Silently absorb cancellation
        } catch let error as URLError where error.code == .cancelled {
            // Silently absorb URLSession cancellation
        } catch {
            if posts.isEmpty {
                errorMessage = ExploreErrorFormatter.message(for: error)
            } else {
                toastMessage = ExploreErrorFormatter.message(for: error)
            }
        }
    }

    func loadMoreIfNeeded(currentPost: ExplorePost) async {
        guard !isLoadingInitialFeed, !isLoadingMore, !hasReachedEndOfFeed else { return }
        guard let currentIndex = posts.firstIndex(where: { $0.id == currentPost.id }) else { return }

        let triggerIndex = max(posts.count - 5, 0)
        guard currentIndex >= triggerIndex else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = try await MerianNetworkClient.shared.getExploreFeed(
                limit: feedPageSize,
                offset: feedOffset
            )

            posts.append(contentsOf: nextPage)
            feedOffset += nextPage.count
            hasReachedEndOfFeed = nextPage.count < feedPageSize
            reconcileActiveCommentsPost()
        } catch is CancellationError {
            // Absorb
        } catch let error as URLError where error.code == .cancelled {
            // Absorb
        } catch {
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func openComments(for post: ExplorePost) async {
        let requestId = beginCommentsSession(for: post)
        await loadCommentsForActivePost(requestId: requestId)
    }

    func openCommentsSheet(for post: ExplorePost) async {
        let requestId = beginCommentsSession(for: post)
        isCommentsSheetPresented = true
        await loadCommentsForActivePost(requestId: requestId)
    }

    func dismissCommentsSheet() {
        isCommentsSheetPresented = false
        dismissComments()
    }

    func dismissComments() {
        activeCommentsRequestId = UUID()
        activeCommentsPostId = nil
        comments = []
        commentDraft = ""
        commentErrorMessage = nil
        isCommentsLoading = false
        isSubmittingComment = false
    }

    func loadCommentsForActivePost(requestId: UUID? = nil) async {
        guard let activeCommentsPostId else { return }
        let resolvedRequestId = requestId ?? UUID()
        activeCommentsRequestId = resolvedRequestId

        isCommentsLoading = true
        commentErrorMessage = nil

        do {
            let loadedComments = try await MerianNetworkClient.shared.getExploreComments(
                postId: activeCommentsPostId,
                limit: commentsPageSize,
                offset: 0
            )
            guard activeCommentsRequestId == resolvedRequestId, self.activeCommentsPostId == activeCommentsPostId else {
                return
            }
            comments = loadedComments
        } catch {
            guard activeCommentsRequestId == resolvedRequestId, self.activeCommentsPostId == activeCommentsPostId else {
                return
            }
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
        }

        if activeCommentsRequestId == resolvedRequestId {
            isCommentsLoading = false
        }
    }

    func toggleLike(for post: ExplorePost) async {
        guard let index = indexForPost(id: post.id) else { return }
        guard !likeRequestsInFlight.contains(post.id) else { return }

        let previousLikedState = posts[index].viewerHasLiked
        let previousLikeCount = posts[index].likeCount
        likeRequestsInFlight.insert(post.id)
        defer { likeRequestsInFlight.remove(post.id) }
        posts[index].viewerHasLiked.toggle()
        posts[index].likeCount = max(0, previousLikeCount + (posts[index].viewerHasLiked ? 1 : -1))

        do {
            let response = try await MerianNetworkClient.shared.setExplorePostLike(
                postId: post.id,
                liked: posts[index].viewerHasLiked
            )
            applyLikeState(
                postId: response.postId,
                likeCount: response.likeCount,
                viewerHasLiked: response.viewerHasLiked
            )
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            applyLikeState(
                postId: post.id,
                likeCount: previousLikeCount,
                viewerHasLiked: previousLikedState
            )
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func submitComment() async {
        guard let activeCommentsPostId else { return }
        guard !isSubmittingComment else { return }

        let trimmed = String(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return }

        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""

        defer { isSubmittingComment = false }

        do {
            let response = try await MerianNetworkClient.shared.createExploreComment(
                postId: activeCommentsPostId,
                body: trimmed
            )
            comments.append(response.comment)
            updateCommentCount(postId: activeCommentsPostId, commentCount: response.commentCount)
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            commentDraft = previousDraft
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }

    func deleteComment(_ comment: ExploreComment) async {
        do {
            let response = try await MerianNetworkClient.shared.deleteExploreComment(commentId: comment.id)
            comments.removeAll { $0.id == response.commentId }
            updateCommentCount(postId: comment.postId, commentCount: response.commentCount)
            HapticManager.shared.triggerSelectionPulse()
            toastMessage = "Comment removed"
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func unshare(_ post: ExplorePost) async {
        guard post.isOwnedByViewer else { return }

        do {
            try await MerianNetworkClient.shared.unshareExplorePost(postId: post.id)
            posts.removeAll { $0.id == post.id }
            if activeCommentsPostId == post.id {
                dismissComments()
            }
            reconcileActiveCommentsPost()
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Removed from Explore"
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func report(_ post: ExplorePost) async {
        let userId = SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId

        do {
            try await MerianNetworkClient.shared.submitFlagIssue(
                scanId: post.scanId,
                flagReason: "Inappropriate content",
                userSuggestion: "Reported from Explore feed",
                userId: userId
            )
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Report submitted. Thanks!"
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func blockAuthor(of post: ExplorePost) async {
        let targetUserId = post.authorUserId
        await SocialGuardManager.shared.blockUser(targetUserId: targetUserId)

        if SocialGuardManager.shared.blockedUserIds.contains(targetUserId) {
            posts.removeAll { $0.authorUserId == targetUserId }
            if activeCommentsPost?.authorUserId == targetUserId {
                dismissComments()
            }
            reconcileActiveCommentsPost()
            toastMessage = "User blocked"
        } else {
            toastMessage = "Could not block this user right now."
        }
    }

    func share(_ post: ExplorePost) {
        var shareText = post.speciesCommonName.capitalized
        if !post.speciesScientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shareText += " (\(post.speciesScientificName))"
        }
        if let publicLocationLabel = post.publicLocationLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !publicLocationLabel.isEmpty {
            shareText += " in \(publicLocationLabel)"
        }

        var items: [Any] = [shareText]
        if let heroImageURL = URL(string: post.heroImageUrl) {
            items.append(heroImageURL)
        }

        ShareSheetUtility.present(items: items)
        HapticManager.shared.triggerSelectionPulse()
    }

    func showNotificationsPlaceholder() {
        HapticManager.shared.triggerSelectionPulse()
        toastMessage = "Explore notifications coming soon"
    }

    private func indexForPost(id: String) -> Int? {
        posts.firstIndex(where: { $0.id == id })
    }

    private func beginCommentsSession(for post: ExplorePost) -> UUID {
        activeCommentsPostId = post.id
        comments = []
        commentDraft = ""
        commentErrorMessage = nil
        let requestId = UUID()
        activeCommentsRequestId = requestId
        return requestId
    }

    private func updateCommentCount(postId: String, commentCount: Int) {
        guard let index = indexForPost(id: postId) else { return }
        posts[index].commentCount = max(0, commentCount)
    }

    private func applyLikeState(postId: String, likeCount: Int, viewerHasLiked: Bool) {
        guard let index = indexForPost(id: postId) else { return }
        posts[index].likeCount = max(0, likeCount)
        posts[index].viewerHasLiked = viewerHasLiked
    }

    private func reconcileActiveCommentsPost() {
        guard let activeCommentsPostId else { return }
        if posts.contains(where: { $0.id == activeCommentsPostId }) == false {
            dismissComments()
        }
    }
}
