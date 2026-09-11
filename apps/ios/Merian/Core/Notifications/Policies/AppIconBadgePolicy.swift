import Foundation

enum AppIconBadgePolicy {
    static let refreshReuseInterval: TimeInterval = 10

    static func normalizedUnreadCount(_ count: Int) -> Int {
        max(0, count)
    }

    static func totalCount(
        hasUnseenScan: Bool,
        exploreUnreadCount: Int
    ) -> Int {
        let unreadCount = normalizedUnreadCount(exploreUnreadCount)
        guard hasUnseenScan else { return unreadCount }

        let (total, overflowed) = unreadCount.addingReportingOverflow(1)
        return overflowed ? Int.max : total
    }

    static func canReuseRefresh(
        force: Bool,
        lastRefreshAt: Date?,
        now: Date
    ) -> Bool {
        guard !force, let lastRefreshAt else { return false }
        let elapsed = now.timeIntervalSince(lastRefreshAt)
        return elapsed >= 0 && elapsed < refreshReuseInterval
    }
}
