import Foundation

extension ExploreFeedViewModel {
    func toggleReaction(for comment: ExploreComment, emoji: String) {
        setCommentReaction(for: comment, emoji: emoji, selected: !(comment.reactions?.first { $0.emoji == emoji }?.viewerHasReacted ?? false))
    }

    func setCommentReaction(for comment: ExploreComment, emoji: String, selected: Bool) {
        Task {
            do {
                _ = try await performCommentReaction(for: comment, emoji: emoji, selected: selected)
            } catch is CancellationError {
            } catch {
                toastMessage = .error(dependencies.errorMessage(error))
            }
        }
    }

    func performCommentReaction(for comment: ExploreComment, emoji: String, selected: Bool) async throws -> ExploreComment {
        let key = "comment:\(comment.id)"
        let generation = activeCommentsRequestId
        let requestedViewer = dependencies.comments.currentViewer().userID
        await reactionMutationQueue.acquire(key)
        defer { reactionRequestsInFlight.remove(key); reactionMutationQueue.release(key) }
        guard !Task.isCancelled, generation == activeCommentsRequestId, requestedViewer == dependencies.comments.currentViewer().userID else { throw CancellationError() }
        reactionRequestsInFlight.insert(key)
        reactionRevisions[key, default: 0] &+= 1
        defer { reactionRevisions[key, default: 0] &+= 1 }
        let viewer = dependencies.comments.currentViewer().userID
        let current = currentReactionComment(comment)
        var optimistic = current
        optimistic.reactions = (current.reactions ?? []).settingReaction(emoji, selected: selected)
        replaceReactionComment(optimistic)
        do {
            let response = try await dependencies.reactions.set(.comment, comment.id, emoji, selected)
            guard !Task.isCancelled, generation == activeCommentsRequestId, viewer == dependencies.comments.currentViewer().userID else { throw CancellationError() }
            var updated = currentReactionComment(optimistic)
            updated.reactions = (updated.reactions ?? []).mergingReaction(response.reaction)
            if generation == activeCommentsRequestId { replaceReactionComment(updated) }
            return updated
        } catch {
            guard generation == activeCommentsRequestId, viewer == dependencies.comments.currentViewer().userID else {
                throw CancellationError()
            }
            replaceReactionComment(current)
            dependencies.feedback.error()
            throw error
        }
    }

    func loadMoreCommentReactions(for comment: ExploreComment) async throws -> ExploreComment {
        let current = currentReactionComment(comment)
        guard let cursor = current.reactionsNextCursor else { return current }
        let key = "comment:\(comment.id)"
        guard reactionPageRequestsInFlight.insert(key).inserted else { throw CancellationError() }
        defer { reactionPageRequestsInFlight.remove(key) }
        let generation = activeCommentsRequestId
        let viewer = dependencies.comments.currentViewer().userID
        let revision = reactionRevisions[key, default: 0]
        let page: ExploreReactionPage
        do {
            page = try await dependencies.reactions.load(.comment, comment.id, cursor)
        } catch {
            guard generation == activeCommentsRequestId, viewer == dependencies.comments.currentViewer().userID,
                  revision == reactionRevisions[key, default: 0] else { throw CancellationError() }
            throw error
        }
        guard !Task.isCancelled, generation == activeCommentsRequestId, viewer == dependencies.comments.currentViewer().userID,
              revision == reactionRevisions[key, default: 0],
              currentReactionComment(current).reactionsNextCursor == cursor,
              !reactionRequestsInFlight.contains(key) else { throw CancellationError() }
        var updated = currentReactionComment(current)
        updated.reactions = page.reactions.reduce(updated.reactions ?? []) { $0.mergingReaction($1) }
        updated.reactionsNextCursor = page.reactionsNextCursor
        if generation == activeCommentsRequestId { replaceReactionComment(updated) }
        return updated
    }

    func preservingNewerCommentReactions(
        in incoming: [ExploreComment], since revisions: [String: UInt64]
    ) -> [ExploreComment] {
        incoming.map { comment in
            let key = "comment:\(comment.id)"
            guard revisions[key, default: 0] != reactionRevisions[key, default: 0]
                    || reactionRequestsInFlight.contains(key) else { return comment }
            let current = currentReactionComment(comment)
            var merged = comment
            merged.reactions = current.reactions
            merged.reactionsNextCursor = current.reactionsNextCursor
            return merged
        }
    }

    private func currentReactionComment(_ fallback: ExploreComment) -> ExploreComment {
        comments.first { $0.id == fallback.id }
            ?? repliesByCommentId[fallback.parentCommentId ?? ""]?.first { $0.id == fallback.id }
            ?? fallback
    }

    private func replaceReactionComment(_ comment: ExploreComment) {
        if let index = comments.firstIndex(where: { $0.id == comment.id }) {
            comments[index].reactions = comment.reactions
            comments[index].reactionsNextCursor = comment.reactionsNextCursor
        }
        if let parent = comment.parentCommentId, let index = repliesByCommentId[parent]?.firstIndex(where: { $0.id == comment.id }) {
            repliesByCommentId[parent]?[index].reactions = comment.reactions
            repliesByCommentId[parent]?[index].reactionsNextCursor = comment.reactionsNextCursor
            markReplyStateChanged()
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
