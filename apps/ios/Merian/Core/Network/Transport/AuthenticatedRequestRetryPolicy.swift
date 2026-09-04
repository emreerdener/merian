import Foundation

enum AuthenticatedRequestRetryPolicy {
    enum UnauthorizedRefreshTarget: Equatable, Sendable {
        case ordinary
        case transitionOwned(AuthTransitionToken)
    }

    private static let safelyReplayableReadFunctionNames: Set<String> = [
        "check-public-username",
        "check-scan-status",
        "get-community-identification-activity",
        "get-community-identification-detail",
        "get-community-identification-feed",
        "get-explore-author-posts",
        "get-explore-author-profile",
        "get-explore-comment-replies",
        "get-explore-comments",
        "get-explore-composer-media",
        "get-explore-feed",
        "get-explore-hashtag-posts",
        "get-explore-map-points",
        "get-explore-media-incidents",
        "get-explore-mention-suggestions",
        "get-explore-notifications",
        "get-explore-post",
        "get-explore-post-detail",
        "get-explore-species-posts",
        "get-explore-unread-notification-count",
        "get-scan-explore-share-state",
        "search-community-taxa",
        "species-dictionary",
        "species-observation-stats"
    ]
    private static let idempotencyAwareFunctionNames: Set<String> = [
        "enrich-scan",
        "explore-post-chat",
        "identify",
        "identify-multimodal",
        "insight-chat",
        "request-community-identification",
        "share-scan-to-explore",
        "species-dictionary-chat",
        "update-explore-field-notes"
    ]

    static func boundUserID(
        explicitUserID: UUID?,
        initiatingUserID: UUID
    ) -> UUID {
        explicitUserID ?? initiatingUserID
    }

    static func canReplayAfterAmbiguousFailure(
        url: URL,
        method: String,
        idempotencyKey: String?
    ) -> Bool {
        if method.caseInsensitiveCompare("GET") == .orderedSame {
            return true
        }
        if idempotencyKey != nil,
           idempotencyAwareFunctionNames.contains(url.lastPathComponent) {
            return true
        }
        return safelyReplayableReadFunctionNames.contains(url.lastPathComponent)
    }

    static func shouldRegenerateSessionAfterUnauthorized(
        responseProvesMissingSession: Bool,
        hasAuthenticatedOAuth: Bool,
        isGuestUser: Bool,
        purchaseIdentityHandoffPending: Bool
    ) -> Bool {
        responseProvesMissingSession
            && !hasAuthenticatedOAuth
            && isGuestUser
            && !purchaseIdentityHandoffPending
    }

    static func unauthorizedRefreshTarget(
        authTransitionOwner: AuthTransitionToken?
    ) -> UnauthorizedRefreshTarget {
        if let authTransitionOwner {
            return .transitionOwned(authTransitionOwner)
        }
        return .ordinary
    }
}
