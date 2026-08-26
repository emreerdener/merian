import Foundation

struct ExplorePostCardViewerContext: Equatable {
    let userID: String?
    let avatarURL: URL?
    let isSubscribed: Bool
}

struct ExplorePostCardAuthorPresentation: Equatable {
    let avatarURL: URL?
    let showsProBadge: Bool

    static func resolve(
        authorAvatarURL: String?,
        authorUserID: String,
        authorIsPro: Bool?,
        isOwnedByViewer: Bool,
        viewer: ExplorePostCardViewerContext
    ) -> Self {
        let remoteAvatarURL = SecureTransportPolicy.httpsURL(from: authorAvatarURL)
        let isCurrentViewer = isOwnedByViewer || viewer.userID == authorUserID

        return Self(
            avatarURL: remoteAvatarURL ?? (isCurrentViewer ? viewer.avatarURL : nil),
            showsProBadge: authorIsPro == true || (isOwnedByViewer && viewer.isSubscribed)
        )
    }
}
