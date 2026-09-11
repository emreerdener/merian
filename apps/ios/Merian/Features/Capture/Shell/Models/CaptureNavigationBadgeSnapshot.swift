/// One atomic refresh result for the Capture workspace navigation badges.
struct CaptureNavigationBadgeSnapshot: Equatable, Sendable {
    let hasUnseenExternalPost: Bool
    let unreadNotificationCount: Int?
}
