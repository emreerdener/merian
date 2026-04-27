import Foundation

extension ExploreFeedViewModel {
    func toggleLike(for post: ExplorePost) async {
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

    func unshare(_ post: ExplorePost) async {
        guard post.isOwnedByViewer else { return }

        do {
            try await MerianNetworkClient.shared.unshareExplorePost(postId: post.id)
            posts.removeAll { $0.id == post.id }
            if activeCommentsPostId == post.id {
                dismissComments()
            }
            reconcileActiveCommentsPost()
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Removed from Explore"
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func report(_ post: ExplorePost) async {
        let userId = SupabaseManager.shared.currentUser?.id.uuidString ?? DeviceIdentityManager.shared.deviceId

        do {
            try await MerianNetworkClient.shared.submitFlagIssue(
                scanId: post.scanId,
                flagReason: "Inappropriate content",
                userSuggestion: "Reported from Explore feed",
                userId: userId
            )
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Report submitted. Thanks!"
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func blockAuthor(of post: ExplorePost) async {
        let targetUserId = post.authorUserId
        await SocialGuardManager.shared.blockUser(targetUserId: targetUserId)

        if SocialGuardManager.shared.blockedUserIds.contains(targetUserId) {
            posts.removeAll { $0.authorUserId == targetUserId }
            if activeCommentsPost?.authorUserId == targetUserId {
                dismissComments()
            }
            reconcileActiveCommentsPost()
            toastMessage = "User blocked"
        } else {
            toastMessage = "Could not block this user right now."
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

    func applyLikeState(postId: String, likeCount: Int, viewerHasLiked: Bool) {
        guard let index = indexForPost(id: postId) else { return }
        posts[index].likeCount = max(0, likeCount)
        posts[index].viewerHasLiked = viewerHasLiked
    }
}
