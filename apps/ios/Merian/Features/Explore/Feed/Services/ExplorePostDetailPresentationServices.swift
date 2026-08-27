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

enum ExplorePostDetailAuthorIdentityPolicy {
    static func changeAffectsAuthor(
        _ authorUserID: String,
        previousUserID: String?,
        currentUserID: String
    ) -> Bool {
        let normalizedAuthorID = authorUserID.lowercased()
        return previousUserID == normalizedAuthorID || currentUserID == normalizedAuthorID
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
