import Foundation

extension ExploreFeedViewModel {
    func loadReplyPreviewIfNeeded(for comment: ExploreComment) async {
        guard (comment.replyCount ?? 0) > 0 else { return }
        guard !hasLoadedReplyPreviewByCommentId.contains(comment.id) else { return }
        guard !hasLoadedRepliesByCommentId.contains(comment.id) else { return }
        guard !loadingReplyPreviewCommentIds.contains(comment.id) else { return }
        guard repliesByCommentId[comment.id]?.isEmpty ?? true else { return }

        let generation = activeCommentsRequestId
        let reactionSnapshot = reactionRevisions
        loadingReplyPreviewCommentIds.insert(comment.id)
        markReplyStateChanged()
        defer {
            if generation == activeCommentsRequestId {
                loadingReplyPreviewCommentIds.remove(comment.id)
                markReplyStateChanged()
            }
        }

        do {
            let replies = try await dependencies.comments.loadReplies(
                comment.id,
                1,
                nil,
                nil
            )
            guard !Task.isCancelled, generation == activeCommentsRequestId,
                  !hasLoadedRepliesByCommentId.contains(comment.id) else { return }
            repliesByCommentId[comment.id] = preservingNewerCommentReactions(in: replies, since: reactionSnapshot)
            hasLoadedReplyPreviewByCommentId.insert(comment.id)
            updateReplyCursor(parentCommentId: comment.id, using: replies)
            markReplyStateChanged()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard generation == activeCommentsRequestId else { return }
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

        let generation = activeCommentsRequestId
        let reactionSnapshot = reactionRevisions
        let task = Task { @MainActor in
            defer {
                if generation == activeCommentsRequestId {
                    loadingReplyCommentIds.remove(comment.id)
                    activeReplyTasks.removeValue(forKey: comment.id)
                    markReplyStateChanged()
                }
            }

            do {
                let replies = try await dependencies.comments.loadReplies(
                    comment.id,
                    repliesPageSize,
                    nil,
                    nil
                )
                guard !Task.isCancelled, generation == activeCommentsRequestId else { return }
                repliesByCommentId[comment.id] = preservingNewerCommentReactions(in: replies, since: reactionSnapshot)
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
                guard generation == activeCommentsRequestId else { return }
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
}
