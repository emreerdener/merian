import Foundation

extension ExploreFeedViewModel {
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

    func beginCommentsSession(for post: ExplorePost) -> UUID {
        activeCommentsPostId = post.id
        comments = []
        commentDraft = ""
        commentErrorMessage = nil
        let requestId = UUID()
        activeCommentsRequestId = requestId
        return requestId
    }

    func updateCommentCount(postId: String, commentCount: Int) {
        guard let index = indexForPost(id: postId) else { return }
        posts[index].commentCount = max(0, commentCount)
    }

    func reconcileActiveCommentsPost() {
        guard let activeCommentsPostId else { return }
        if posts.contains(where: { $0.id == activeCommentsPostId }) == false {
            dismissComments()
        }
    }
}
