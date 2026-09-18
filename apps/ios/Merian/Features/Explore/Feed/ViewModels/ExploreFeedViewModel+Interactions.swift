import Foundation

enum ExploreShareMessageFormatter {
    static func message(
        commonName: String,
        postId: String,
        primaryMediaKind: ExploreMediaKind?
    ) -> String {
        let introduction = primaryMediaKind == .audio ? "Listen to" : "Check out"
        return "\(introduction) this \(commonName)\n\(PublicBrand.websiteURL(path: "explore/post/\(postId)").absoluteString)"
    }
}

extension ExploreFeedViewModel {
    func toggleLike(for post: ExplorePost) async {
        await setPostLike(for: post, selected: nil)
    }

    /// A nil selection is a direct heart-button toggle. Picker selections are idempotent.
    func setPostLike(for post: ExplorePost, selected: Bool?) async {
        let key = "post:\(post.id)"
        let generation = activeFeedRequestId
        let viewer = dependencies.comments.currentViewer().userID
        let removalRevision = postRemovalRevisions[post.id, default: 0]
        await reactionMutationQueue.acquire(key)
        defer { reactionMutationQueue.release(key) }
        guard !Task.isCancelled, generation == activeFeedRequestId,
              viewer == dependencies.comments.currentViewer().userID,
              removalRevision == postRemovalRevisions[post.id, default: 0] else { return }
        if self.post(id: post.id) == nil { upsertPost(post) }
        if let selected, self.post(id: post.id)?.viewerHasLiked == selected { return }
        reactionRevisions[key, default: 0] &+= 1
        let revision = reactionRevisions[key]
        defer {
            reactionRevisions[key, default: 0] &+= 1
            postReactorsRevision &+= 1
        }

        guard let optimisticState = store.toggleLikeOptimistically(postId: post.id),
              let optimisticPost = store.post(id: post.id) else {
            return
        }

        let previousLikedState = optimisticState.previousLikedState
        let previousLikeCount = optimisticState.previousLikeCount
        likeRequestsInFlight.insert(post.id)
        defer { likeRequestsInFlight.remove(post.id) }

        do {
            let response = try await dependencies.interactions.setLike(
                post.id,
                optimisticPost.viewerHasLiked
            )
            guard generation == activeFeedRequestId, viewer == dependencies.comments.currentViewer().userID,
                  revision == reactionRevisions[key], self.post(id: post.id) != nil else { return }
            applyLikeState(
                postId: response.postId,
                likeCount: response.likeCount,
                viewerHasLiked: response.viewerHasLiked
            )
            // Picker taps already acknowledge selection in the shared reaction UI.
            if selected == nil { dependencies.feedback.selection() }
        } catch {
            guard generation == activeFeedRequestId, viewer == dependencies.comments.currentViewer().userID,
                  revision == reactionRevisions[key], self.post(id: post.id) != nil else { return }
            applyLikeState(
                postId: post.id,
                likeCount: previousLikeCount,
                viewerHasLiked: previousLikedState
            )
            dependencies.feedback.error()
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    @discardableResult
    func unshare(_ post: ExplorePost) async -> Bool {
        guard post.isOwnedByViewer else { return false }

        do {
            try await dependencies.interactions.unsharePost(post.id)
            ExploreShareStateStore.setSharedPostId(nil, for: post.scanId)
            dependencies.interactions.sendShareStateChanged(post.scanId, nil)
            removePost(id: post.id)
            dependencies.feedback.success()
            toastMessage = .success("Removed from Explore")
            return true
        } catch {
            dependencies.feedback.error()
            toastMessage = .error(dependencies.errorMessage(error))
            return false
        }
    }

    @discardableResult
    func report(_ post: ExplorePost) async -> Bool {
        do {
            try await dependencies.interactions.reportPost(post.id)
            removePost(id: post.id)
            dependencies.feedback.success()
            toastMessage = .success("Report submitted. Thanks!")
            return true
        } catch {
            dependencies.feedback.error()
            toastMessage = .error(dependencies.errorMessage(error))
            return false
        }
    }

    @discardableResult
    func blockAuthor(of post: ExplorePost) async -> Bool {
        let targetUserId = post.authorUserId
        if await dependencies.interactions.blockAuthor(targetUserId) {
            removePosts(byAuthorUserId: targetUserId)
            toastMessage = .success("User blocked")
            return true
        } else {
            toastMessage = .error("Could not block this user right now.")
            return false
        }
    }

    func share(_ post: ExplorePost, playbackCoordinator: ExploreVideoPlaybackCoordinator? = nil) {
        let shareText = ExploreShareMessageFormatter.message(
            commonName: resolvedSpeciesCommonName(for: post),
            postId: post.id,
            primaryMediaKind: post.resolvedMediaItems.first?.kind
        )

        let overlayToken = playbackCoordinator?.beginOverlay(reason: "explore-share-sheet")
        ShareSheetPresenter.present(items: [shareText]) {
            guard let overlayToken else { return }
            playbackCoordinator?.endOverlay(overlayToken)
        }
        dependencies.feedback.selection()
    }

    func indexForPost(id: String) -> Int? {
        posts.firstIndex(where: { $0.id == id })
    }

    func upsertPost(_ post: ExplorePost, includeInFeed: Bool = false) {
        store.upsert(post, includeInFeed: includeInFeed)
        reconcileActiveCommentsPost()
    }

    func refreshPost(postId: String) async {
        let key = "post:\(postId)"
        let generation = activeFeedRequestId
        let viewer = dependencies.comments.currentViewer().userID
        let removalRevision = postRemovalRevisions[postId, default: 0]
        await reactionMutationQueue.acquire(key)
        defer { reactionMutationQueue.release(key) }
        guard !Task.isCancelled, generation == activeFeedRequestId,
              viewer == dependencies.comments.currentViewer().userID,
              removalRevision == postRemovalRevisions[postId, default: 0] else { return }
        reactionRevisions[key, default: 0] &+= 1
        let revision = reactionRevisions[key]
        defer { reactionRevisions[key, default: 0] &+= 1 }
        do {
            let refreshedPost = try await dependencies.interactions.loadPost(postId)
            guard !Task.isCancelled, generation == activeFeedRequestId,
                  revision == reactionRevisions[key], viewer == dependencies.comments.currentViewer().userID else { return }
            upsertPost(refreshedPost)
        } catch {
            guard generation == activeFeedRequestId, revision == reactionRevisions[key],
                  viewer == dependencies.comments.currentViewer().userID else { return }
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func removePost(id: String) {
        postRemovalRevisions[id, default: 0] &+= 1
        reactionRevisions["post:\(id)", default: 0] &+= 1
        store.removePost(id: id)
        if activeCommentsPostId == id {
            dismissComments()
        }
        reconcileActiveCommentsPost()
    }

    func removePosts(byAuthorUserId authorUserId: String) {
        for post in store.allPosts where post.authorUserId == authorUserId {
            postRemovalRevisions[post.id, default: 0] &+= 1
            reactionRevisions["post:\(post.id)", default: 0] &+= 1
        }
        store.removePosts(byAuthorUserId: authorUserId)
        if activeCommentsPost?.authorUserId == authorUserId {
            dismissComments()
        }
        reconcileActiveCommentsPost()
    }

    func applyLikeState(postId: String, likeCount: Int, viewerHasLiked: Bool) {
        store.applyLikeState(postId: postId, likeCount: likeCount, viewerHasLiked: viewerHasLiked)
    }
}
