import Foundation

extension ExploreFeedViewModel {
    func toggleReaction(for comment: ExploreComment, emoji: String) {
        let updatedComment = comment.applyingReactionToggle(emoji: emoji)
        dependencies.feedback.medium()

        if let parentCommentId = updatedComment.parentCommentId,
           var replies = repliesByCommentId[parentCommentId],
           let index = replies.firstIndex(where: { $0.id == updatedComment.id }) {
            replies[index] = updatedComment
            repliesByCommentId[parentCommentId] = replies
            markReplyStateChanged()
        } else if let index = comments.firstIndex(where: { $0.id == updatedComment.id }) {
            comments[index] = updatedComment
        }

        Task {
            do {
                try await dependencies.comments.toggleReaction(comment.id, emoji)
            } catch {
                MerianLog.network.error("Failed to toggle reaction: \(error)")
            }
        }
    }

    func markReplyStateChanged() {
        replyStateVersion &+= 1
        refreshReplyThreadRenderStates()
    }

    private func refreshReplyThreadRenderStates() {
        let parentCommentIds = Set(repliesByCommentId.keys)
            .union(expandedReplyCommentIds)
            .union(loadingReplyCommentIds)
            .union(loadingReplyPreviewCommentIds)
            .union(loadingMoreReplyCommentIds)
            .union(failedReplyCommentIds)
            .union(hasLoadedReplyPreviewByCommentId)
            .union(hasLoadedRepliesByCommentId)
            .union(hasReachedEndOfRepliesByCommentId)

        var nextStates: [String: ExploreReplyThreadRenderState] = [:]
        for parentCommentId in parentCommentIds {
            nextStates[parentCommentId] = currentReplyThreadRenderState(for: parentCommentId)
        }
        replyThreadRenderStates = nextStates
    }

    func currentReplyThreadRenderState(for parentCommentId: String) -> ExploreReplyThreadRenderState {
        ExploreReplyThreadRenderState(
            replies: repliesByCommentId[parentCommentId] ?? [],
            isExpanded: expandedReplyCommentIds.contains(parentCommentId),
            isLoading: loadingReplyCommentIds.contains(parentCommentId),
            isLoadingPreview: loadingReplyPreviewCommentIds.contains(parentCommentId),
            isLoadingMore: loadingMoreReplyCommentIds.contains(parentCommentId),
            didFail: failedReplyCommentIds.contains(parentCommentId),
            hasLoadedPreview: hasLoadedReplyPreviewByCommentId.contains(parentCommentId),
            hasLoadedReplies: hasLoadedRepliesByCommentId.contains(parentCommentId),
            hasReachedEnd: hasReachedEndOfRepliesByCommentId.contains(parentCommentId)
        )
    }
}
