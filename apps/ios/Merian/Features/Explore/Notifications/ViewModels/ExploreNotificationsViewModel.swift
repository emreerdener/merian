import Foundation
import Observation

@MainActor
@Observable
final class ExploreNotificationsViewModel {
    var notifications: [ExploreNotification] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var recentlyReadNotificationIds = Set<String>()

    @ObservationIgnored private let pageSize = 50
    @ObservationIgnored private var nextCursorUpdatedAt: String?
    @ObservationIgnored private var nextCursorNotificationId: String?
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var hasReachedEnd = false

    func fetchNotifications(force: Bool = false) async -> Bool {
        guard !isLoading else { return false }

        isLoading = true
        errorMessage = nil
        recentlyReadNotificationIds = []
        if force {
            hasReachedEnd = false
            nextCursorUpdatedAt = nil
            nextCursorNotificationId = nil
        }
        defer { isLoading = false }

        do {
            let loadedNotifications = try await MerianNetworkClient.shared.getExploreNotifications(limit: pageSize)
            notifications = visibleNotifications(loadedNotifications)
            hasLoadedOnce = true
            hasReachedEnd = loadedNotifications.count < pageSize
            updateCursor(using: loadedNotifications)

            let unreadIds = Set(loadedNotifications.filter { !$0.isRead }.map(\.id))
            guard !unreadIds.isEmpty else {
                recentlyReadNotificationIds = []
                return false
            }

            _ = try await MerianNetworkClient.shared.markExploreNotificationsRead()
            recentlyReadNotificationIds = unreadIds
            notifications = notifications.map { notification in
                var updatedNotification = notification
                updatedNotification.isRead = true
                return updatedNotification
            }
            return true
        } catch is CancellationError {
            return false
        } catch let error as URLError where error.code == .cancelled {
            return false
        } catch {
            MerianLog.network.error(
                "Explore notifications fetch failed: \(error.localizedDescription, privacy: .private)"
            )
            AppTelemetry.trackExploreNotificationsFetchFailed(context: "sheet_load")
            errorMessage = ExploreErrorFormatter.message(for: error)
            return false
        }
    }

    func loadMoreIfNeeded(currentNotification: ExploreNotification) async {
        guard hasLoadedOnce, !isLoading, !isLoadingMore, !hasReachedEnd else { return }
        guard let currentIndex = notifications.firstIndex(where: { $0.id == currentNotification.id }) else { return }

        let triggerIndex = max(notifications.count - 8, 0)
        guard currentIndex >= triggerIndex else { return }
        guard let nextCursorUpdatedAt, let nextCursorNotificationId else {
            hasReachedEnd = true
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let nextPage = try await MerianNetworkClient.shared.getExploreNotifications(
                limit: pageSize,
                beforeUpdatedAt: nextCursorUpdatedAt,
                beforeNotificationId: nextCursorNotificationId
            )
            appendUniqueNotifications(visibleNotifications(nextPage))
            hasReachedEnd = nextPage.count < pageSize
            updateCursor(using: nextPage)
        } catch is CancellationError {
            // Absorb cancellation while the sheet is being dismissed.
        } catch let error as URLError where error.code == .cancelled {
            // Absorb URLSession cancellation.
        } catch {
            MerianLog.network.error(
                "Explore notifications pagination failed: \(error.localizedDescription, privacy: .private)"
            )
            AppTelemetry.trackExploreNotificationsFetchFailed(context: "pagination")
        }
    }

    private func updateCursor(using page: [ExploreNotification]) {
        nextCursorUpdatedAt = page.last?.updatedAt
        nextCursorNotificationId = page.last?.id
    }

    private func appendUniqueNotifications(_ page: [ExploreNotification]) {
        guard !page.isEmpty else { return }

        let existingIds = Set(notifications.map(\.id))
        notifications.append(contentsOf: page.filter { existingIds.contains($0.id) == false })
    }

    private func visibleNotifications(_ page: [ExploreNotification]) -> [ExploreNotification] {
        guard !FieldTripsAvailability.isEnabled else { return page }
        return page.filter { !$0.type.isFieldTripNotification }
    }

    func markAllAsRead() async {
        _ = try? await MerianNetworkClient.shared.markExploreNotificationsRead()
        recentlyReadNotificationIds.removeAll()
        for i in notifications.indices {
            notifications[i].isRead = true
        }
    }
}
