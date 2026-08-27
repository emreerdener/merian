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
            let loadedComments = try await dependencies.comments.loadComments(
                activeCommentsPostId,
                commentsPageSize,
                nil,
                nil
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
            commentErrorMessage = dependencies.errorMessage(error)
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
            let nextPage = try await dependencies.comments.loadComments(
                activeCommentsPostId,
                commentsPageSize,
                nextCommentsCursorCreatedAt,
                nextCommentsCursorCommentId
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
            commentErrorMessage = dependencies.errorMessage(error)
        }
    }

    func submitComment() async {
        guard let submissionPostId = activeCommentsPostId else { return }
        guard !isSubmittingComment else { return }

        let trimmed = String(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return }

        let submissionSessionId = activeCommentsRequestId
        let replyParent = replyingToComment
        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""
        composerResetToken = UUID()

        defer {
            if isActiveCommentsSession(postId: submissionPostId, requestId: submissionSessionId) {
                isSubmittingComment = false
            }
        }

        do {
            let response = try await dependencies.comments.createComment(
                submissionPostId,
                trimmed,
                replyParent?.id
            )
            guard isActiveCommentsSession(postId: submissionPostId, requestId: submissionSessionId) else { return }

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

            updateCommentCount(postId: submissionPostId, commentCount: response.commentCount)
            dependencies.feedback.success()
        } catch {
            guard isActiveCommentsSession(postId: submissionPostId, requestId: submissionSessionId) else { return }
            commentDraft = previousDraft
            composerResetToken = UUID()
            commentErrorMessage = dependencies.errorMessage(error)
            dependencies.feedback.error()
        }
    }

    func removeComment(_ comment: ExploreComment) async {
        do {
            let response = try await dependencies.comments.deleteComment(comment.id)
            removeCommentLocally(comment)
            updateCommentCount(postId: comment.postId, commentCount: response.commentCount)
            dependencies.feedback.selection()
            let successMessage = comment.removalSuccessMessage
            toastMessage = .success(successMessage)
        } catch {
            dependencies.feedback.error()
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func reportComment(_ comment: ExploreComment) async {
        do {
            try await dependencies.comments.reportComment(comment.id)
            dependencies.feedback.success()
            toastMessage = .success("Report submitted. Thanks!")
        } catch {
            dependencies.feedback.error()
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func beginReply(to comment: ExploreComment) {
        replyingToComment = comment
        commentErrorMessage = nil
        dependencies.feedback.selection()
    }

    func cancelReply() {
        replyingToComment = nil
        dependencies.feedback.selection()
    }

    func replyThreadRenderState(for commentId: String) -> ExploreReplyThreadRenderState {
        replyThreadRenderStates[commentId] ?? currentReplyThreadRenderState(for: commentId)
    }

    func expandReplies(for comment: ExploreComment) {
        dependencies.feedback.sheet()
        guard !expandedReplyCommentIds.contains(comment.id) else { return }

        expandedReplyCommentIds.insert(comment.id)
        markReplyStateChanged()
    }

    func expandRepliesAndLoad(for comment: ExploreComment) async {
        expandReplies(for: comment)
        if !hasLoadedRepliesByCommentId.contains(comment.id),
           !loadingReplyCommentIds.contains(comment.id) {
            await loadReplies(for: comment)
        }
    }

    func loadReplyPreviewIfNeeded(for comment: ExploreComment) async {
        guard (comment.replyCount ?? 0) > 0 else { return }
        guard !hasLoadedReplyPreviewByCommentId.contains(comment.id) else { return }
        guard !hasLoadedRepliesByCommentId.contains(comment.id) else { return }
        guard !loadingReplyPreviewCommentIds.contains(comment.id) else { return }
        guard repliesByCommentId[comment.id]?.isEmpty ?? true else { return }

        loadingReplyPreviewCommentIds.insert(comment.id)
        markReplyStateChanged()
        defer {
            loadingReplyPreviewCommentIds.remove(comment.id)
            markReplyStateChanged()
        }

        do {
            let replies = try await dependencies.comments.loadReplies(
                comment.id,
                1,
                nil,
                nil
            )
            guard !hasLoadedRepliesByCommentId.contains(comment.id) else { return }
            repliesByCommentId[comment.id] = replies
            hasLoadedReplyPreviewByCommentId.insert(comment.id)
            updateReplyCursor(parentCommentId: comment.id, using: replies)
            markReplyStateChanged()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            MerianLog.network.error(
                "Explore reply preview load failed: \(error.localizedDescription, privacy: .private)"
            )
            commentErrorMessage = dependencies.errorMessage(error)
        }
    }

    func loadReplies(for comment: ExploreComment) async {
        guard !hasLoadedRepliesByCommentId.contains(comment.id) else { return }

        if let existingTask = activeReplyTasks[comment.id] {
            _ = await existingTask.value
            return
        }

        loadingReplyCommentIds.insert(comment.id)
        failedReplyCommentIds.remove(comment.id)
        markReplyStateChanged()
        commentErrorMessage = nil

        let task = Task { @MainActor in
            defer {
                loadingReplyCommentIds.remove(comment.id)
                activeReplyTasks.removeValue(forKey: comment.id)
                markReplyStateChanged()
            }

            do {
                let replies = try await dependencies.comments.loadReplies(
                    comment.id,
                    repliesPageSize,
                    nil,
                    nil
                )
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
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                MerianLog.network.error(
                    "Explore reply load failed: \(error.localizedDescription, privacy: .private)"
                )
                commentErrorMessage = dependencies.errorMessage(error)
                failedReplyCommentIds.insert(comment.id)
                dependencies.feedback.error()
            }
        }

        activeReplyTasks[comment.id] = task
        _ = await task.value
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
            let nextPage = try await dependencies.comments.loadReplies(
                parentComment.id,
                repliesPageSize,
                cursor.createdAt,
                cursor.commentId
            )
            appendUniqueReplies(nextPage, parentCommentId: parentComment.id)
            if nextPage.count < repliesPageSize {
                hasReachedEndOfRepliesByCommentId.insert(parentComment.id)
                markReplyStateChanged()
            }
            updateReplyCursor(parentCommentId: parentComment.id, using: nextPage)
        } catch {
            commentErrorMessage = dependencies.errorMessage(error)
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
                let nextPage = try await dependencies.comments.loadComments(
                    activeCommentsPostId,
                    commentsPageSize,
                    cursorCreatedAt,
                    cursorCommentId
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
                commentErrorMessage = dependencies.errorMessage(error)
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
                let nextPage = try await dependencies.comments.loadReplies(
                    parentComment.id,
                    repliesPageSize,
                    cursor.createdAt,
                    cursor.commentId
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
                commentErrorMessage = dependencies.errorMessage(error)
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
        isSubmittingComment = false
        let requestId = UUID()
        activeCommentsRequestId = requestId
        nextCommentsCursorCreatedAt = nil
        nextCommentsCursorCommentId = nil
        hasLoadedCommentsOnce = false
        hasReachedEndOfComments = false
        return requestId
    }

    private func isActiveCommentsSession(postId: String, requestId: UUID) -> Bool {
        activeCommentsPostId == postId && activeCommentsRequestId == requestId
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
        for task in activeReplyTasks.values {
            task.cancel()
        }
        activeReplyTasks = [:]

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
        replyThreadRenderStates = [:]
        if !keepingPendingExpansion {
            pendingExpandedReplyParentCommentId = nil
        }
        markReplyStateChanged()
    }

}
