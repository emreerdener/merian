import Foundation

extension Array where Element == ExploreCommentReaction {
    func mergingReaction(_ reaction: ExploreCommentReaction) -> Self {
        var result = filter { $0.emoji != reaction.emoji }
        if reaction.count >= 1 { result.append(reaction) }
        return result.sorted {
            let lhs = $0.order ?? ExploreEmojiCatalog.order(for: $0.emoji)
            let rhs = $1.order ?? ExploreEmojiCatalog.order(for: $1.emoji)
            return lhs == rhs ? $0.emoji < $1.emoji : lhs < rhs
        }
    }

    func settingReaction(_ emoji: String, selected: Bool) -> Self {
        var reaction = first { $0.emoji == emoji } ?? .init(emoji: emoji, count: 0, viewerHasReacted: false)
        if reaction.viewerHasReacted != selected { reaction.count = Swift.max(0, reaction.count + (selected ? 1 : -1)) }
        reaction.viewerHasReacted = selected
        return mergingReaction(reaction)
    }
}

extension ExploreFeedViewModel {
    func preservingNewerReactions(in incoming: [ExplorePost], since revisions: [String: UInt64]) -> [ExplorePost] {
        incoming.compactMap { incomingPost in
            let key = "post:\(incomingPost.id)"
            if revisions[key, default: 0] != reactionRevisions[key, default: 0],
               postRemovalRevisions[incomingPost.id, default: 0] > 0, post(id: incomingPost.id) == nil {
                return nil
            }
            guard revisions[key, default: 0] != reactionRevisions[key, default: 0]
                || reactionRequestsInFlight.contains(key) || likeRequestsInFlight.contains(incomingPost.id),
                let current = post(id: incomingPost.id)
            else { return incomingPost }
            var merged = incomingPost
            merged.reactions = current.reactions
            merged.reactionsNextCursor = current.reactionsNextCursor
            merged.likeCount = current.likeCount
            merged.viewerHasLiked = current.viewerHasLiked
            return merged
        }
    }

    /// Detail reads share the post owner's mutation fence so a late read cannot undo a tap.
    func loadPostDetailReactions(
        postId: String, load: @MainActor () async -> ExplorePostDetail?
    ) async {
        let key = "post:\(postId)"
        let generation = activeFeedRequestId
        let viewer = dependencies.comments.currentViewer().userID
        let revision = reactionRevisions[key, default: 0]
        let detail = await load()
        guard !Task.isCancelled, generation == activeFeedRequestId,
              viewer == dependencies.comments.currentViewer().userID,
              revision == reactionRevisions[key, default: 0],
              !reactionRequestsInFlight.contains(key), !likeRequestsInFlight.contains(postId),
              detail?.postId == postId, let reactions = detail?.reactions,
              post(id: postId) != nil else { return }
        store.applyReactions(postId: postId, reactions: reactions, cursor: detail?.reactionsNextCursor)
    }

    func hydratePostReactions(for source: ExplorePost) async {
        let viewer = dependencies.comments.currentViewer().userID
        let generation = activeFeedRequestId
        let key = "post:\(source.id)"
        let removalRevision = postRemovalRevisions[source.id, default: 0]
        await reactionMutationQueue.acquire(key)
        defer { reactionMutationQueue.release(key) }
        guard !Task.isCancelled, generation == activeFeedRequestId,
              viewer == dependencies.comments.currentViewer().userID,
              removalRevision == postRemovalRevisions[source.id, default: 0],
              post(id: source.id)?.reactions == nil else { return }
        let revision = reactionRevisions[key, default: 0]
        do {
            let hydrated = try await dependencies.interactions.loadPost(source.id)
            guard !Task.isCancelled, generation == activeFeedRequestId,
                revision == reactionRevisions["post:\(source.id)", default: 0],
                viewer == dependencies.comments.currentViewer().userID,
                !reactionRequestsInFlight.contains("post:\(source.id)"), !likeRequestsInFlight.contains(source.id)
            else { return }
            upsertPost(hydrated)
        } catch { /* Opening detail or refreshing provides the existing retry path. */  }
    }

    func setPostReaction(for source: ExplorePost, emoji: String, selected: Bool) async {
        if emoji == "❤️" {
            await setPostLike(for: source, selected: selected)
            return
        }
        let key = "post:\(source.id)"
        let generation = activeFeedRequestId
        let requestedViewer = dependencies.comments.currentViewer().userID
        let removalRevision = postRemovalRevisions[source.id, default: 0]
        await hydratePostReactions(for: source)
        await reactionMutationQueue.acquire(key)
        defer {
            reactionRequestsInFlight.remove(key)
            reactionMutationQueue.release(key)
        }
        guard !Task.isCancelled, generation == activeFeedRequestId,
            requestedViewer == dependencies.comments.currentViewer().userID,
            removalRevision == postRemovalRevisions[source.id, default: 0]
        else { return }
        reactionRequestsInFlight.insert(key)
        reactionRevisions[key, default: 0] &+= 1
        let revision = reactionRevisions[key]
        defer {
            reactionRevisions[key, default: 0] &+= 1
            postReactorsRevision &+= 1
        }
        if post(id: source.id) == nil { upsertPost(source) }
        guard let current = post(id: source.id) else { return }
        let previous = current.reactions ?? []
        let viewer = dependencies.comments.currentViewer().userID
        store.applyReactions(
            postId: source.id, reactions: previous.settingReaction(emoji, selected: selected),
            cursor: current.reactionsNextCursor)
        do {
            let response = try await dependencies.reactions.set(.post, source.id, emoji, selected)
            guard generation == activeFeedRequestId,
                revision == reactionRevisions[key], viewer == dependencies.comments.currentViewer().userID,
                let latest = post(id: source.id)
            else { return }
            store.applyReactions(
                postId: source.id, reactions: (latest.reactions ?? []).mergingReaction(response.reaction),
                cursor: latest.reactionsNextCursor)
        } catch {
            guard generation == activeFeedRequestId, revision == reactionRevisions[key],
                viewer == dependencies.comments.currentViewer().userID,
                post(id: source.id) != nil
            else { return }
            store.applyReactions(postId: source.id, reactions: previous, cursor: current.reactionsNextCursor)
            toastMessage = .error(ExploreErrorFormatter.reactionMutationMessage(selected: selected))
            dependencies.feedback.error()
        }
    }

    func loadMorePostReactions(for source: ExplorePost) async {
        guard let current = post(id: source.id), let cursor = current.reactionsNextCursor,
            reactionPageRequestsInFlight.insert("post:\(source.id)").inserted
        else { return }
        defer { reactionPageRequestsInFlight.remove("post:\(source.id)") }
        let generation = activeFeedRequestId
        let revision = reactionRevisions["post:\(source.id)", default: 0]
        let viewer = dependencies.comments.currentViewer().userID
        do {
            let page = try await dependencies.reactions.load(.post, source.id, cursor)
            guard generation == activeFeedRequestId, viewer == dependencies.comments.currentViewer().userID,
                let latest = post(id: source.id), latest.reactionsNextCursor == cursor,
                revision == reactionRevisions["post:\(source.id)", default: 0],
                !reactionRequestsInFlight.contains("post:\(source.id)"), !likeRequestsInFlight.contains(source.id)
            else { return }
            let merged = page.reactions.reduce(latest.reactions ?? []) { $0.mergingReaction($1) }
            store.applyReactions(postId: source.id, reactions: merged, cursor: page.reactionsNextCursor)
        } catch {
            guard generation == activeFeedRequestId, viewer == dependencies.comments.currentViewer().userID,
                  revision == reactionRevisions["post:\(source.id)", default: 0] else { return }
            toastMessage = .error("Couldn’t load more reactions. Please try again.")
        }
    }
}
