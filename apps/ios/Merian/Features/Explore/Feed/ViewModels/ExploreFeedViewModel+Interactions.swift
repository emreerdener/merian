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
        upsertPost(post)
        guard !likeRequestsInFlight.contains(post.id) else { return }

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
            applyLikeState(
                postId: response.postId,
                likeCount: response.likeCount,
                viewerHasLiked: response.viewerHasLiked
            )
            dependencies.feedback.selection()
        } catch {
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
        ShareSheetUtility.present(items: [shareText]) {
            guard let overlayToken else { return }
            Task { @MainActor in
                playbackCoordinator?.endOverlay(overlayToken)
            }
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
        do {
            let refreshedPost = try await dependencies.interactions.loadPost(postId)
            upsertPost(refreshedPost)
        } catch {
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func removePost(id: String) {
        store.removePost(id: id)
        if activeCommentsPostId == id {
            dismissComments()
        }
        reconcileActiveCommentsPost()
    }

    func removePosts(byAuthorUserId authorUserId: String) {
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
