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
        resetReplyState()
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
            resetReplyState(keepingPendingExpansion: true)
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

        let replyParent = replyingToComment
        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""
        composerResetToken = UUID()

        defer { isSubmittingComment = false }

        do {
            let response = try await MerianNetworkClient.shared.createExploreComment(
                postId: activeCommentsPostId,
                body: trimmed,
                parentCommentId: replyParent?.id
            )

            if let parentId = response.comment.parentCommentId ?? replyParent?.id {
                appendReply(response.comment, parentCommentId: parentId)
                replyingToComment = nil
            } else {
                comments.append(response.comment)
                hasLoadedCommentsOnce = true
                if hasReachedEndOfComments {
                    updateCommentsCursor(using: comments)
                } else if nextCommentsCursorCreatedAt == nil || nextCommentsCursorCommentId == nil {
                    updateCommentsCursor(using: comments)
                    hasReachedEndOfComments = comments.count < commentsPageSize
                }
            }

            updateCommentCount(postId: activeCommentsPostId, commentCount: response.commentCount)
            HapticManager.shared.triggerSuccessPulse()
        } catch {
            commentDraft = previousDraft
            composerResetToken = UUID()
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }

    func removeComment(_ comment: ExploreComment) async {
        do {
            let response = try await MerianNetworkClient.shared.deleteExploreComment(commentId: comment.id)
            removeCommentLocally(comment)
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

    func beginReply(to comment: ExploreComment) {
        replyingToComment = comment
        commentErrorMessage = nil
        HapticManager.shared.triggerSelectionPulse()
    }

    func cancelReply() {
        replyingToComment = nil
        HapticManager.shared.triggerSelectionPulse()
    }

    func expandReplies(for comment: ExploreComment) {
        HapticManager.shared.triggerSheetSpring()
        guard !expandedReplyCommentIds.contains(comment.id) else { return }

        expandedReplyCommentIds.insert(comment.id)
        markReplyStateChanged()
    }

    func loadReplyPreviewIfNeeded(for comment: ExploreComment) async {
        print("[RepliesDebug] loadReplyPreviewIfNeeded started for comment \(comment.id). replyCount: \(comment.replyCount ?? 0)")
        guard (comment.replyCount ?? 0) > 0 else {
            print("[RepliesDebug] loadReplyPreviewIfNeeded aborted: replyCount is 0 or nil")
            return
        }
        guard !hasLoadedReplyPreviewByCommentId.contains(comment.id) else {
            print("[RepliesDebug] loadReplyPreviewIfNeeded aborted: already loaded preview")
            return
        }
        guard !hasLoadedRepliesByCommentId.contains(comment.id) else {
            print("[RepliesDebug] loadReplyPreviewIfNeeded aborted: already loaded full replies")
            return
        }
        guard !loadingReplyPreviewCommentIds.contains(comment.id) else {
            print("[RepliesDebug] loadReplyPreviewIfNeeded aborted: already loading preview")
            return
        }
        guard repliesByCommentId[comment.id]?.isEmpty ?? true else {
            print("[RepliesDebug] loadReplyPreviewIfNeeded aborted: replies list is not empty")
            return
        }

        print("[RepliesDebug] loadReplyPreviewIfNeeded proceeding to fetch for comment \(comment.id)")
        loadingReplyPreviewCommentIds.insert(comment.id)
        markReplyStateChanged()
        defer {
            loadingReplyPreviewCommentIds.remove(comment.id)
            markReplyStateChanged()
            print("[RepliesDebug] loadReplyPreviewIfNeeded defer finished for comment \(comment.id)")
        }

        do {
            let replies = try await MerianNetworkClient.shared.getExploreCommentReplies(
                parentCommentId: comment.id,
                limit: 1
            )
            print("[RepliesDebug] loadReplyPreviewIfNeeded fetch successful: fetched \(replies.count) replies for comment \(comment.id)")
            guard !hasLoadedRepliesByCommentId.contains(comment.id) else {
                print("[RepliesDebug] loadReplyPreviewIfNeeded aborted post-fetch: full replies loaded in parallel")
                return
            }
            repliesByCommentId[comment.id] = replies
            hasLoadedReplyPreviewByCommentId.insert(comment.id)
            updateReplyCursor(parentCommentId: comment.id, using: replies)
            markReplyStateChanged()
        } catch is CancellationError {
            print("[RepliesDebug] loadReplyPreviewIfNeeded task cancelled for comment \(comment.id)")
        } catch let error as URLError where error.code == .cancelled {
            print("[RepliesDebug] loadReplyPreviewIfNeeded URLSession cancelled for comment \(comment.id)")
        } catch {
            print("[RepliesDebug] loadReplyPreviewIfNeeded failed with error: \(error) for comment \(comment.id)")
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func loadReplies(for comment: ExploreComment) async {
        print("[RepliesDebug] loadReplies started for comment \(comment.id)")
        guard !hasLoadedRepliesByCommentId.contains(comment.id) else {
            print("[RepliesDebug] loadReplies aborted: already loaded full replies")
            return
        }
        guard !loadingReplyCommentIds.contains(comment.id) else {
            print("[RepliesDebug] loadReplies aborted: already loading full replies")
            return
        }

        print("[RepliesDebug] loadReplies proceeding to fetch for comment \(comment.id)")
        loadingReplyCommentIds.insert(comment.id)
        failedReplyCommentIds.remove(comment.id)
        markReplyStateChanged()
        commentErrorMessage = nil
        defer {
            loadingReplyCommentIds.remove(comment.id)
            markReplyStateChanged()
            print("[RepliesDebug] loadReplies defer finished for comment \(comment.id)")
        }

        do {
            let replies = try await MerianNetworkClient.shared.getExploreCommentReplies(
                parentCommentId: comment.id,
                limit: repliesPageSize
            )
            print("[RepliesDebug] loadReplies fetch successful: fetched \(replies.count) replies for comment \(comment.id)")
            repliesByCommentId[comment.id] = replies
            hasLoadedReplyPreviewByCommentId.insert(comment.id)
            hasLoadedRepliesByCommentId.insert(comment.id)
            if replies.count < repliesPageSize {
                hasReachedEndOfRepliesByCommentId.insert(comment.id)
            } else {
                hasReachedEndOfRepliesByCommentId.remove(comment.id)
            }
            updateReplyCursor(parentCommentId: comment.id, using: replies)
            markReplyStateChanged()
        } catch is CancellationError {
            print("[RepliesDebug] loadReplies task cancelled for comment \(comment.id)")
        } catch let error as URLError where error.code == .cancelled {
            print("[RepliesDebug] loadReplies URLSession cancelled for comment \(comment.id)")
        } catch {
            print("[RepliesDebug] loadReplies failed with error: \(error) for comment \(comment.id)")
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            failedReplyCommentIds.insert(comment.id)
            HapticManager.shared.triggerErrorThump()
        }
    }


    func loadMoreRepliesIfNeeded(parentComment: ExploreComment, currentReply: ExploreComment) async {
        guard hasLoadedRepliesByCommentId.contains(parentComment.id),
              !loadingReplyCommentIds.contains(parentComment.id),
              !loadingMoreReplyCommentIds.contains(parentComment.id),
              !hasReachedEndOfRepliesByCommentId.contains(parentComment.id),
              let replies = repliesByCommentId[parentComment.id],
              let currentIndex = replies.firstIndex(where: { $0.id == currentReply.id }) else {
            return
        }

        let triggerIndex = max(replies.count - 5, 0)
        guard currentIndex >= triggerIndex else { return }
        guard let cursor = replyCursorsByCommentId[parentComment.id] else {
            hasReachedEndOfRepliesByCommentId.insert(parentComment.id)
            markReplyStateChanged()
            return
        }

        loadingMoreReplyCommentIds.insert(parentComment.id)
        markReplyStateChanged()
        defer {
            loadingMoreReplyCommentIds.remove(parentComment.id)
            markReplyStateChanged()
        }

        do {
            let nextPage = try await MerianNetworkClient.shared.getExploreCommentReplies(
                parentCommentId: parentComment.id,
                limit: repliesPageSize,
                afterCreatedAt: cursor.createdAt,
                afterCommentId: cursor.commentId
            )
            appendUniqueReplies(nextPage, parentCommentId: parentComment.id)
            if nextPage.count < repliesPageSize {
                hasReachedEndOfRepliesByCommentId.insert(parentComment.id)
                markReplyStateChanged()
            }
            updateReplyCursor(parentCommentId: parentComment.id, using: nextPage)
        } catch {
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func prepareToExpandReplyThread(parentCommentId: String?) {
        pendingExpandedReplyParentCommentId = parentCommentId
    }

    func expandPendingReplyThreadIfNeeded() async {
        guard let parentCommentId = pendingExpandedReplyParentCommentId else { return }
        await loadCommentsUntilCommentIfNeeded(commentId: parentCommentId)
        guard let parentComment = comments.first(where: { $0.id == parentCommentId }) else {
            return
        }
        pendingExpandedReplyParentCommentId = nil
        expandedReplyCommentIds.insert(parentCommentId)
        markReplyStateChanged()
        if !hasLoadedRepliesByCommentId.contains(parentCommentId) {
            await loadReplies(for: parentComment)
        }
    }

    func expandReplyThread(parentCommentId: String, targetReplyId: String? = nil) async {
        await loadCommentsUntilCommentIfNeeded(commentId: parentCommentId)
        guard let parentComment = comments.first(where: { $0.id == parentCommentId }) else {
            return
        }

        pendingExpandedReplyParentCommentId = nil
        expandedReplyCommentIds.insert(parentCommentId)
        markReplyStateChanged()

        if !hasLoadedRepliesByCommentId.contains(parentCommentId) {
            await loadReplies(for: parentComment)
        }

        if let targetReplyId {
            await loadRepliesUntilReplyIfNeeded(parentComment: parentComment, replyId: targetReplyId)
        }
    }

    func loadCommentsUntilCommentIfNeeded(commentId: String) async {
        guard comments.contains(where: { $0.id == commentId }) == false else { return }
        guard hasLoadedCommentsOnce, !hasReachedEndOfComments else { return }
        guard let activeCommentsPostId else { return }

        while !Task.isCancelled,
              comments.contains(where: { $0.id == commentId }) == false,
              !hasReachedEndOfComments,
              let cursorCreatedAt = nextCommentsCursorCreatedAt,
              let cursorCommentId = nextCommentsCursorCommentId {
            let resolvedRequestId = activeCommentsRequestId
            isLoadingMoreComments = true

            do {
                let nextPage = try await MerianNetworkClient.shared.getExploreComments(
                    postId: activeCommentsPostId,
                    limit: commentsPageSize,
                    afterCreatedAt: cursorCreatedAt,
                    afterCommentId: cursorCommentId
                )
                guard activeCommentsRequestId == resolvedRequestId, self.activeCommentsPostId == activeCommentsPostId else {
                    isLoadingMoreComments = false
                    return
                }

                appendUniqueComments(nextPage)
                hasReachedEndOfComments = nextPage.count < commentsPageSize
                updateCommentsCursor(using: nextPage)
                isLoadingMoreComments = false
            } catch {
                isLoadingMoreComments = false
                guard activeCommentsRequestId == resolvedRequestId, self.activeCommentsPostId == activeCommentsPostId else {
                    return
                }
                commentErrorMessage = ExploreErrorFormatter.message(for: error)
                return
            }
        }
    }

    func loadRepliesUntilReplyIfNeeded(parentComment: ExploreComment, replyId: String) async {
        guard repliesByCommentId[parentComment.id]?.contains(where: { $0.id == replyId }) != true else { return }
        guard hasLoadedRepliesByCommentId.contains(parentComment.id),
              !hasReachedEndOfRepliesByCommentId.contains(parentComment.id) else {
            return
        }

        while !Task.isCancelled,
              repliesByCommentId[parentComment.id]?.contains(where: { $0.id == replyId }) != true,
              !hasReachedEndOfRepliesByCommentId.contains(parentComment.id),
              let cursor = replyCursorsByCommentId[parentComment.id] {
            loadingMoreReplyCommentIds.insert(parentComment.id)
            markReplyStateChanged()

            do {
                let nextPage = try await MerianNetworkClient.shared.getExploreCommentReplies(
                    parentCommentId: parentComment.id,
                    limit: repliesPageSize,
                    afterCreatedAt: cursor.createdAt,
                    afterCommentId: cursor.commentId
                )
                appendUniqueReplies(nextPage, parentCommentId: parentComment.id)
                if nextPage.count < repliesPageSize {
                    hasReachedEndOfRepliesByCommentId.insert(parentComment.id)
                    markReplyStateChanged()
                }
                updateReplyCursor(parentCommentId: parentComment.id, using: nextPage)
                loadingMoreReplyCommentIds.remove(parentComment.id)
                markReplyStateChanged()
            } catch {
                loadingMoreReplyCommentIds.remove(parentComment.id)
                markReplyStateChanged()
                commentErrorMessage = ExploreErrorFormatter.message(for: error)
                return
            }
        }
    }

    func beginCommentsSession(for post: ExplorePost) -> UUID {
        activeCommentsPostId = post.id
        comments = []
        resetReplyState(keepingPendingExpansion: true)
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

    private func appendReply(_ reply: ExploreComment, parentCommentId: String) {
        var replies = repliesByCommentId[parentCommentId] ?? []
        if replies.contains(where: { $0.id == reply.id }) == false {
            replies.append(reply)
        }
        repliesByCommentId[parentCommentId] = replies
        expandedReplyCommentIds.insert(parentCommentId)
        hasLoadedRepliesByCommentId.insert(parentCommentId)
        hasLoadedReplyPreviewByCommentId.insert(parentCommentId)
        if let index = comments.firstIndex(where: { $0.id == parentCommentId }) {
            comments[index].replyCount = (comments[index].replyCount ?? 0) + 1
        }
        updateReplyCursor(parentCommentId: parentCommentId, using: replies)
        markReplyStateChanged()
    }

    private func appendUniqueReplies(_ nextPage: [ExploreComment], parentCommentId: String) {
        guard !nextPage.isEmpty else { return }

        let existingReplies = repliesByCommentId[parentCommentId] ?? []
        let existingIds = Set(existingReplies.map(\.id))
        repliesByCommentId[parentCommentId] = existingReplies + nextPage.filter { existingIds.contains($0.id) == false }
        markReplyStateChanged()
    }

    private func updateReplyCursor(parentCommentId: String, using page: [ExploreComment]) {
        guard let lastReply = page.last else { return }
        replyCursorsByCommentId[parentCommentId] = ExploreCommentCursor(
            createdAt: lastReply.createdAt,
            commentId: lastReply.id
        )
    }

    private func removeCommentLocally(_ comment: ExploreComment) {
        if let parentCommentId = comment.parentCommentId {
            repliesByCommentId[parentCommentId]?.removeAll { $0.id == comment.id }
            if let index = comments.firstIndex(where: { $0.id == parentCommentId }) {
                comments[index].replyCount = max((comments[index].replyCount ?? 1) - 1, 0)
            }
            markReplyStateChanged()
            return
        }

        comments.removeAll { $0.id == comment.id }
        repliesByCommentId[comment.id] = nil
        expandedReplyCommentIds.remove(comment.id)
        hasLoadedRepliesByCommentId.remove(comment.id)
        hasLoadedReplyPreviewByCommentId.remove(comment.id)
        hasReachedEndOfRepliesByCommentId.remove(comment.id)
        failedReplyCommentIds.remove(comment.id)
        replyCursorsByCommentId[comment.id] = nil
        markReplyStateChanged()
    }

    private func resetReplyState(keepingPendingExpansion: Bool = false) {
        replyingToComment = nil
        repliesByCommentId = [:]
        expandedReplyCommentIds = []
        loadingReplyCommentIds = []
        loadingReplyPreviewCommentIds = []
        loadingMoreReplyCommentIds = []
        failedReplyCommentIds = []
        replyCursorsByCommentId = [:]
        hasLoadedReplyPreviewByCommentId = []
        hasLoadedRepliesByCommentId = []
        hasReachedEndOfRepliesByCommentId = []
        if !keepingPendingExpansion {
            pendingExpandedReplyParentCommentId = nil
        }
        markReplyStateChanged()
    }

    func toggleReaction(for comment: ExploreComment, emoji: String) {
        guard let updatedComment = commentWithUpdatedReaction(comment, emoji: emoji) else { return }
        HapticManager.shared.triggerMediumPulse()

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
                try await MerianNetworkClient.shared.toggleExploreCommentReaction(commentId: comment.id, emoji: emoji)
            } catch {
                MerianLog.network.error("Failed to toggle reaction: \(error)")
            }
        }
    }

    private func commentWithUpdatedReaction(_ comment: ExploreComment, emoji: String) -> ExploreComment? {
        var updatedComment = comment
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
            updatedReactions.append(ExploreCommentReaction(emoji: emoji, count: 1, viewerHasReacted: true))
        }

        updatedComment.reactions = updatedReactions
        return updatedComment
    }

    private func markReplyStateChanged() {
        replyStateVersion &+= 1
    }
}
