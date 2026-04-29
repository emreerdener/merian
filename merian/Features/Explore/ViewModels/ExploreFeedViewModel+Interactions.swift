import Foundation

extension ExploreFeedViewModel {
    func toggleLike(for post: ExplorePost) async {
        upsertPost(post)
        guard let index = indexForPost(id: post.id) else { return }
        guard !likeRequestsInFlight.contains(post.id) else { return }

        let previousLikedState = posts[index].viewerHasLiked
        let previousLikeCount = posts[index].likeCount
        likeRequestsInFlight.insert(post.id)
        defer { likeRequestsInFlight.remove(post.id) }
        posts[index].viewerHasLiked.toggle()
        posts[index].likeCount = max(0, previousLikeCount + (posts[index].viewerHasLiked ? 1 : -1))

        do {
            let response = try await MerianNetworkClient.shared.setExplorePostLike(
                postId: post.id,
                liked: posts[index].viewerHasLiked
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
        var shareText = post.speciesCommonName.capitalized
        if !post.speciesScientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shareText += " (\(post.speciesScientificName))"
        }
        if let publicLocationLabel = post.publicLocationLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !publicLocationLabel.isEmpty {
            shareText += " in \(publicLocationLabel)"
        }

        var items: [Any] = [shareText]
        if let heroImageURL = URL(string: post.heroImageUrl) {
            items.append(heroImageURL)
        }

        ShareSheetUtility.present(items: items)
        HapticManager.shared.triggerSelectionPulse()
    }

    func indexForPost(id: String) -> Int? {
        posts.firstIndex(where: { $0.id == id })
    }

    func upsertPost(_ post: ExplorePost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        } else {
            posts.append(post)
        }
        reconcileActiveCommentsPost()
    }

    func removePost(id: String) {
        posts.removeAll { $0.id == id }
        if activeCommentsPostId == id {
            dismissComments()
        }
        reconcileActiveCommentsPost()
    }

    func removePosts(byAuthorUserId authorUserId: String) {
        posts.removeAll { $0.authorUserId == authorUserId }
        if activeCommentsPost?.authorUserId == authorUserId {
            dismissComments()
        }
        reconcileActiveCommentsPost()
    }

    func applyLikeState(postId: String, likeCount: Int, viewerHasLiked: Bool) {
        guard let index = indexForPost(id: postId) else { return }
        posts[index].likeCount = max(0, likeCount)
        posts[index].viewerHasLiked = viewerHasLiked
    }
}
