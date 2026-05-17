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
        isLoadingMoreComments = false
        isSubmittingComment = false
        nextCommentsCursorCreatedAt = nil
        nextCommentsCursorCommentId = nil
        hasLoadedCommentsOnce = false
        hasReachedEndOfComments = false
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
                limit: commentsPageSize
            )
            guard activeCommentsRequestId == resolvedRequestId, self.activeCommentsPostId == activeCommentsPostId else {
                return
            }
            comments = loadedComments
            hasLoadedCommentsOnce = true
            hasReachedEndOfComments = loadedComments.count < commentsPageSize
            updateCommentsCursor(using: loadedComments)
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

    func loadMoreCommentsIfNeeded(currentComment: ExploreComment) async {
        guard hasLoadedCommentsOnce, !isCommentsLoading, !isLoadingMoreComments, !hasReachedEndOfComments else { return }
        guard let activeCommentsPostId else { return }
        guard let currentIndex = comments.firstIndex(where: { $0.id == currentComment.id }) else { return }

        let triggerIndex = max(comments.count - 8, 0)
        guard currentIndex >= triggerIndex else { return }
        guard let nextCommentsCursorCreatedAt, let nextCommentsCursorCommentId else {
            hasReachedEndOfComments = true
            return
        }

        let resolvedRequestId = activeCommentsRequestId
        isLoadingMoreComments = true
        defer { isLoadingMoreComments = false }

        do {
            let nextPage = try await MerianNetworkClient.shared.getExploreComments(
                postId: activeCommentsPostId,
                limit: commentsPageSize,
                afterCreatedAt: nextCommentsCursorCreatedAt,
                afterCommentId: nextCommentsCursorCommentId
            )
            guard activeCommentsRequestId == resolvedRequestId, self.activeCommentsPostId == activeCommentsPostId else {
                return
            }

            appendUniqueComments(nextPage)
            hasReachedEndOfComments = nextPage.count < commentsPageSize
            updateCommentsCursor(using: nextPage)
        } catch is CancellationError {
            // Absorb cancellation while comments are being dismissed.
        } catch let error as URLError where error.code == .cancelled {
            // Absorb URLSession cancellation.
        } catch {
            guard activeCommentsRequestId == resolvedRequestId, self.activeCommentsPostId == activeCommentsPostId else {
                return
            }
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
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
            hasLoadedCommentsOnce = true
            if hasReachedEndOfComments {
                updateCommentsCursor(using: comments)
            } else if nextCommentsCursorCreatedAt == nil || nextCommentsCursorCommentId == nil {
                updateCommentsCursor(using: comments)
                hasReachedEndOfComments = comments.count < commentsPageSize
            }
            updateCommentCount(postId: activeCommentsPostId, commentCount: response.commentCount)
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            commentDraft = previousDraft
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }

    func removeComment(_ comment: ExploreComment) async {
        do {
            let response = try await MerianNetworkClient.shared.deleteExploreComment(commentId: comment.id)
            comments.removeAll { $0.id == response.commentId }
            updateCommentCount(postId: comment.postId, commentCount: response.commentCount)
            HapticManager.shared.triggerSelectionPulse()
            toastMessage = comment.removalSuccessMessage
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func reportComment(_ comment: ExploreComment) async {
        do {
            try await MerianNetworkClient.shared.reportExploreComment(commentId: comment.id)
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Report submitted. Thanks!"
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
        nextCommentsCursorCreatedAt = nil
        nextCommentsCursorCommentId = nil
        hasLoadedCommentsOnce = false
        hasReachedEndOfComments = false
        return requestId
    }

    func updateCommentCount(postId: String, commentCount: Int) {
        store.updateCommentCount(postId: postId, commentCount: commentCount)
    }

    func reconcileActiveCommentsPost() {
        guard let activeCommentsPostId else { return }
        if store.post(id: activeCommentsPostId) == nil {
            dismissComments()
        }
    }

    private func updateCommentsCursor(using page: [ExploreComment]) {
        nextCommentsCursorCreatedAt = page.last?.createdAt
        nextCommentsCursorCommentId = page.last?.id
    }

    private func appendUniqueComments(_ nextPage: [ExploreComment]) {
        guard !nextPage.isEmpty else { return }

        let existingIds = Set(comments.map(\.id))
        comments.append(contentsOf: nextPage.filter { existingIds.contains($0.id) == false })
    }

    func toggleReaction(for comment: ExploreComment, emoji: String) {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        
        var updatedComment = comments[index]
        var updatedReactions = updatedComment.reactions ?? []
        
        if let reactionIndex = updatedReactions.firstIndex(where: { $0.emoji == emoji }) {
            var reaction = updatedReactions[reactionIndex]
            if reaction.viewerHasReacted {
                reaction.count -= 1
                reaction.viewerHasReacted = false
                if reaction.count < 1 {
                    updatedReactions.remove(at: reactionIndex)
                } else {
                    updatedReactions[reactionIndex] = reaction
                }
            } else {
                reaction.count += 1
                reaction.viewerHasReacted = true
                updatedReactions[reactionIndex] = reaction
            }
        } else {
            let newReaction = ExploreCommentReaction(emoji: emoji, count: 1, viewerHasReacted: true)
            updatedReactions.append(newReaction)
        }
        
        updatedComment.reactions = updatedReactions
        comments[index] = updatedComment
        HapticManager.shared.triggerSelectionPulse()
        
        Task {
            do {
                try await MerianNetworkClient.shared.toggleExploreCommentReaction(commentId: comment.id, emoji: emoji)
            } catch {
                MerianLog.network.error("Failed to toggle reaction: \(error)")
                // Note: Revert logic omitted until backend is deployed to allow UI testing
            }
        }
    }
}
