import Foundation
import Observation

@MainActor
@Observable
final class ExploreNotificationReplyThreadViewModel {
    typealias ReactionHandler = @MainActor (_ comment: ExploreComment, _ emoji: String, _ selected: Bool) async throws -> ExploreComment

    var parentComment: ExploreComment?
    var replies: [ExploreComment] = []
    var reactingCommentId: String?
    var isLoading = true
    var isLoadingMoreReplies = false
    var hasReachedEndOfReplies = true
    var errorMessage: String?

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let onToggleReaction: ReactionHandler
    @ObservationIgnored private let loadReactions: @MainActor (ExploreComment) async throws -> ExploreComment
    @ObservationIgnored private let reactionQueue = ExploreReactionMutationQueue()
    @ObservationIgnored private var pendingReactions = Set<String>()
    @ObservationIgnored private var activeRoute: ExploreNotificationReplyThreadRoute?
    @ObservationIgnored private var nextReplyCursor: ExploreCommentCursor?
    @ObservationIgnored private var loadGeneration = UUID()
    @ObservationIgnored private var activePaginationRequestId: UUID?

    init(
        dependencies: Dependencies = .live,
        onToggleReaction: @escaping ReactionHandler = { comment, _, _ in comment },
        loadReactions: @escaping @MainActor (ExploreComment) async throws -> ExploreComment = { $0 }
    ) {
        self.dependencies = dependencies
        self.onToggleReaction = onToggleReaction
        self.loadReactions = loadReactions
    }

    func load(route: ExploreNotificationReplyThreadRoute) async {
        let generation = UUID()
        loadGeneration = generation
        activePaginationRequestId = nil
        activeRoute = route
        isLoading = true
        isLoadingMoreReplies = false
        errorMessage = nil
        reactionError = nil
        parentComment = nil
        replies = []
        hasReachedEndOfReplies = true
        nextReplyCursor = nil

        defer {
            if isActive(route: route, generation: generation) {
                isLoading = false
            }
        }

        do {
            async let parentTask = loadParentCommentIfPossible(route: route)
            async let repliesTask = loadRepliesThroughTarget(route: route)
            let (loadedParent, loadedReplies) = try await (parentTask, repliesTask)
            guard isActive(route: route, generation: generation) else { return }

            parentComment = loadedParent
            replies = repliesWithFallback(loadedReplies.replies, route: route)
            hasReachedEndOfReplies = loadedReplies.hasReachedEnd
            nextReplyCursor = loadedReplies.nextCursor
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard isActive(route: route, generation: generation) else { return }
            errorMessage = dependencies.errorMessage(error)
        }
    }

    func loadMoreReplies() async {
        guard let route = activeRoute,
              let parentCommentId = route.parentCommentId,
              !isLoading,
              !isLoadingMoreReplies,
              !hasReachedEndOfReplies,
              let nextReplyCursor else { return }

        let generation = loadGeneration
        let requestId = UUID()
        activePaginationRequestId = requestId
        isLoadingMoreReplies = true
        defer {
            if isActive(route: route, generation: generation),
               activePaginationRequestId == requestId {
                isLoadingMoreReplies = false
            }
        }

        do {
            let page = try await dependencies.loadReplies(
                parentCommentId,
                dependencies.repliesPageSize,
                nextReplyCursor.createdAt,
                nextReplyCursor.commentId
            )
            guard isActive(route: route, generation: generation),
                  activePaginationRequestId == requestId else { return }

            mergeReplies(page, into: &replies)
            replies = repliesWithFallback(replies, route: route)
            hasReachedEndOfReplies = page.count < dependencies.repliesPageSize
            self.nextReplyCursor = hasReachedEndOfReplies
                ? nil
                : page.last.map { ExploreCommentCursor(createdAt: $0.createdAt, commentId: $0.id) }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard isActive(route: route, generation: generation),
                  activePaginationRequestId == requestId else { return }
            errorMessage = dependencies.errorMessage(error)
        }
    }

    func toggleReaction(for comment: ExploreComment, emoji: String) {
        setReaction(for: comment, emoji: emoji, selected: !(comment.reactions?.first { $0.emoji == emoji }?.viewerHasReacted ?? false))
    }

    func setReaction(for comment: ExploreComment, emoji: String, selected: Bool) {
        let generation = loadGeneration
        let viewer = dependencies.currentViewer().userID
        Task {
            await reactionQueue.acquire(comment.id)
            defer { pendingReactions.remove(comment.id); reactionQueue.release(comment.id) }
            guard generation == loadGeneration, viewer == dependencies.currentViewer().userID,
                  !Task.isCancelled else { return }
            pendingReactions.insert(comment.id)
            let current = parentComment?.id == comment.id ? parentComment! : replies.first { $0.id == comment.id } ?? comment
            var optimistic = current
            optimistic.reactions = (current.reactions ?? []).settingReaction(emoji, selected: selected)
            replaceReactionComment(optimistic)
            do {
                let updated = try await onToggleReaction(current, emoji, selected)
                guard generation == loadGeneration, viewer == dependencies.currentViewer().userID,
                      !Task.isCancelled else { return }
                replaceReactionComment(updated)
            } catch {
                guard generation == loadGeneration, viewer == dependencies.currentViewer().userID else { return }
                replaceReactionComment(current)
                if !(error is CancellationError) {
                    reactionError = ExploreErrorFormatter.reactionMutationMessage(selected: selected)
                }
            }
        }
    }

    var reactionError: String?
    func loadMoreReactions(for comment: ExploreComment) {
        guard pendingReactions.insert(comment.id).inserted else { return }
        let generation = loadGeneration
        let viewer = dependencies.currentViewer().userID
        Task {
            await reactionQueue.acquire(comment.id)
            defer { pendingReactions.remove(comment.id); reactionQueue.release(comment.id) }
            guard generation == loadGeneration, viewer == dependencies.currentViewer().userID,
                  !Task.isCancelled else { return }
            let current = parentComment?.id == comment.id
                ? parentComment! : replies.first { $0.id == comment.id } ?? comment
            do {
                let updated = try await loadReactions(current)
                guard generation == loadGeneration, viewer == dependencies.currentViewer().userID, !Task.isCancelled else { return }
                replaceReactionComment(updated)
            } catch is CancellationError {
                return
            } catch {
                guard generation == loadGeneration, viewer == dependencies.currentViewer().userID else { return }
                reactionError = "Could not load reactions. Try again."
            }
        }
    }

    private func replaceReactionComment(_ comment: ExploreComment) {
        if parentComment?.id == comment.id { parentComment?.reactions = comment.reactions; parentComment?.reactionsNextCursor = comment.reactionsNextCursor }
        if let index = replies.firstIndex(where: { $0.id == comment.id }) { replies[index].reactions = comment.reactions; replies[index].reactionsNextCursor = comment.reactionsNextCursor }
    }

    func authorAvatarURL(for comment: ExploreComment) -> URL? {
        guard let post = activeRoute?.post else { return nil }
        return ExploreCommentAuthorPresentation.avatarURL(
            for: comment,
            post: post,
            viewer: dependencies.currentViewer()
        )
    }

    private func loadParentCommentIfPossible(
        route: ExploreNotificationReplyThreadRoute
    ) async throws -> ExploreComment? {
        guard let parentCommentId = route.parentCommentId else { return nil }

        var cursor: ExploreCommentCursor?
        for _ in 0..<dependencies.maximumPageCount {
            try Task.checkCancellation()
            let page = try await dependencies.loadComments(
                route.post.id,
                dependencies.commentsPageSize,
                cursor?.createdAt,
                cursor?.commentId
            )

            if let comment = page.first(where: { $0.id == parentCommentId }) {
                return comment
            }

            guard page.count == dependencies.commentsPageSize,
                  let lastComment = page.last else { break }
            cursor = ExploreCommentCursor(
                createdAt: lastComment.createdAt,
                commentId: lastComment.id
            )
        }

        return nil
    }

    private func loadRepliesThroughTarget(
        route: ExploreNotificationReplyThreadRoute
    ) async throws -> LoadedRepliesPage {
        guard let parentCommentId = route.parentCommentId else {
            return LoadedRepliesPage(replies: [], hasReachedEnd: true, nextCursor: nil)
        }

        var loadedReplies: [ExploreComment] = []
        var cursor: ExploreCommentCursor?
        var hasReachedEnd = true

        for _ in 0..<dependencies.maximumPageCount {
            try Task.checkCancellation()
            let page = try await dependencies.loadReplies(
                parentCommentId,
                dependencies.repliesPageSize,
                cursor?.createdAt,
                cursor?.commentId
            )

            mergeReplies(page, into: &loadedReplies)
            hasReachedEnd = page.count < dependencies.repliesPageSize

            if loadedReplies.contains(where: { $0.id == route.targetReplyId }) || hasReachedEnd {
                let nextCursor = page.last.map {
                    ExploreCommentCursor(createdAt: $0.createdAt, commentId: $0.id)
                }
                return LoadedRepliesPage(
                    replies: loadedReplies,
                    hasReachedEnd: hasReachedEnd,
                    nextCursor: hasReachedEnd ? nil : nextCursor
                )
            }

            guard let lastReply = page.last else { break }
            cursor = ExploreCommentCursor(
                createdAt: lastReply.createdAt,
                commentId: lastReply.id
            )
        }

        return LoadedRepliesPage(
            replies: loadedReplies,
            hasReachedEnd: hasReachedEnd,
            nextCursor: cursor
        )
    }

    private func repliesWithFallback(
        _ loadedReplies: [ExploreComment],
        route: ExploreNotificationReplyThreadRoute
    ) -> [ExploreComment] {
        guard loadedReplies.contains(where: { $0.id == route.targetReplyId }) == false,
              let fallbackReplyComment = fallbackReplyComment(route: route) else {
            return loadedReplies
        }

        return [fallbackReplyComment] + loadedReplies
    }

    private func fallbackReplyComment(
        route: ExploreNotificationReplyThreadRoute
    ) -> ExploreComment? {
        guard let body = route.fallbackReply.body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else { return nil }

        return ExploreComment(
            commentId: route.fallbackReply.commentId,
            postId: route.post.id,
            parentCommentId: route.parentCommentId,
            authorUserId: route.fallbackReply.authorUserId ?? "",
            authorName: route.fallbackReply.authorName ?? "Someone",
            authorUsername: nil,
            authorAvatarUrl: nil,
            body: body,
            createdAt: route.fallbackReply.createdAt,
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: false,
            replyCount: nil,
            reactions: nil,
            mentions: nil
        )
    }

    private func mergeReplies(
        _ page: [ExploreComment],
        into replies: inout [ExploreComment]
    ) {
        var indicesById: [String: Int] = [:]
        for index in replies.indices {
            indicesById[replies[index].id] = index
        }

        for comment in page {
            if let existingIndex = indicesById[comment.id] {
                replies[existingIndex] = comment
            } else {
                indicesById[comment.id] = replies.endIndex
                replies.append(comment)
            }
        }
    }

    private func isActive(
        route: ExploreNotificationReplyThreadRoute,
        generation: UUID
    ) -> Bool {
        loadGeneration == generation && activeRoute?.id == route.id
    }
}

private struct LoadedRepliesPage {
    let replies: [ExploreComment]
    let hasReachedEnd: Bool
    let nextCursor: ExploreCommentCursor?
}
