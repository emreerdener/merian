import Foundation

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
            let response = try await MerianNetworkClient.shared.setExplorePostLike(
                postId: post.id,
                liked: optimisticPost.viewerHasLiked
            )
            applyLikeState(
                postId: response.postId,
                likeCount: response.likeCount,
                viewerHasLiked: response.viewerHasLiked
            )
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            applyLikeState(
                postId: post.id,
                likeCount: previousLikeCount,
                viewerHasLiked: previousLikedState
            )
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    @discardableResult
    func unshare(_ post: ExplorePost) async -> Bool {
        guard post.isOwnedByViewer else { return false }

        do {
            try await MerianNetworkClient.shared.unshareExplorePost(postId: post.id)
            ExploreShareStateStore.setSharedPostId(nil, for: post.scanId)
            AppEventPublisher.shared.send(.exploreShareStateChanged(scanId: post.scanId, postId: nil))
            removePost(id: post.id)
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Removed from Explore"
            return true
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
            return false
        }
    }

    @discardableResult
    func report(_ post: ExplorePost) async -> Bool {
        let userId = SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId

        do {
            try await MerianNetworkClient.shared.submitFlagIssue(
                scanId: post.scanId,
                flagReason: "Inappropriate content",
                userSuggestion: "Reported from Explore feed",
                userId: userId
            )
            removePost(id: post.id)
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Report submitted. Thanks!"
            return true
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
            return false
        }
    }

    @discardableResult
    func blockAuthor(of post: ExplorePost) async -> Bool {
        let targetUserId = post.authorUserId
        await SocialGuardManager.shared.blockUser(targetUserId: targetUserId)

        if SocialGuardManager.shared.blockedUserIds.contains(targetUserId) {
            removePosts(byAuthorUserId: targetUserId)
            toastMessage = "User blocked"
            return true
        } else {
            toastMessage = "Could not block this user right now."
            return false
        }
    }

    func share(_ post: ExplorePost) {
        var shareText = "Check out this Merian Explore post: \(resolvedSpeciesCommonName(for: post))"
        if !post.speciesScientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shareText += " (\(post.speciesScientificName))"
        }
        if let publicLocationLabel = post.publicDisplayLocationLabel {
            shareText += " in \(publicLocationLabel)"
        }

        shareText += "\nhttps://merian.earth/explore/post/\(post.id)"

        ShareSheetUtility.present(items: [shareText])
        HapticManager.shared.triggerSelectionPulse()
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
            let refreshedPost = try await MerianNetworkClient.shared.getExplorePost(postId: postId)
            upsertPost(refreshedPost)
        } catch {
            toastMessage = ExploreErrorFormatter.message(for: error)
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
