enum NotificationPreference: Equatable {
    case discovery
    case achievements
    case explore
    case exploreCommentMentions
    case communityIdentifications

    var remoteRegistrationReason: String? {
        switch self {
        case .discovery, .achievements:
            nil
        case .explore:
            "explore_setting_changed"
        case .exploreCommentMentions:
            "explore_comment_mentions_setting_changed"
        case .communityIdentifications:
            "community_identifications_setting_changed"
        }
    }

    var enabledAfterAuthorizationReason: String? {
        switch self {
        case .discovery, .achievements:
            nil
        case .explore:
            "explore_setting_enabled_after_authorization"
        case .exploreCommentMentions:
            "explore_comment_mentions_setting_enabled_after_authorization"
        case .communityIdentifications:
            "community_identifications_setting_enabled_after_authorization"
        }
    }
}
