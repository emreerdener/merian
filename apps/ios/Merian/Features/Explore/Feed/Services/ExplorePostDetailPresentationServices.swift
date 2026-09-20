import Foundation

struct ExplorePostDetailPresentationServices {
    let currentViewer: @MainActor () -> ExplorePostCardViewerContext
    let isProActive: @MainActor () -> Bool
    let trackFieldChatTapped: @MainActor (
        _ postId: String,
        _ scientificName: String,
        _ isProActive: Bool
    ) -> Void
}

extension ExplorePostDetailPresentationServices {
    @MainActor
    func isOwnedByCurrentUser(_ post: ExplorePost) -> Bool {
        let viewer = currentViewer()
        return post.isOwnedByViewer || viewer.userID == post.authorUserId
    }

    @MainActor
    func authorPresentation(
        for post: ExplorePost
    ) -> ExplorePostCardAuthorPresentation {
        ExplorePostCardAuthorPresentation.resolve(
            authorAvatarURL: post.authorAvatarUrl,
            authorUserID: post.authorUserId,
            authorIsPro: post.authorIsPro,
            isOwnedByViewer: post.isOwnedByViewer,
            viewer: currentViewer()
        )
    }
}

enum ExplorePostDetailRefreshPolicy {
    static func postIDToRefresh(
        for event: AppEvent,
        postID: String,
        currentPost: ExplorePost?
    ) -> String? {
        switch event {
        case .explorePostNeedsRefresh(let changedPostID) where changedPostID == postID:
            return changedPostID
        case .publicAuthorIdentityChanged(let previousUserID, let currentUserID):
            guard let post = currentPost else { return nil }
            let authorID = post.authorUserId.lowercased()
            return previousUserID == authorID || currentUserID == authorID ? post.id : nil
        default:
            return nil
        }
    }
}

extension ExplorePostDetailPresentationServices {
    static let live = Self(
        currentViewer: {
            ExplorePostCardViewerContext(
                userID: SupabaseManager.shared.currentUser?.id.uuidString,
                avatarURL: SupabaseManager.shared.currentUserAvatarUrl,
                isSubscribed: RevenueCatManager.shared.isSubscribed
            )
        },
        isProActive: { RevenueCatManager.shared.isProActive },
        trackFieldChatTapped: { postId, scientificName, isProActive in
            PostHogManager.shared.capture(
                "ExplorePostFieldChatTapped",
                properties: [
                    "post_id": postId,
                    "species_scientific_name": scientificName,
                    "is_pro": isProActive
                ]
            )
        }
    )
}
