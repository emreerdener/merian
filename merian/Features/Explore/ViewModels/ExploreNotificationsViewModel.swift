import Foundation
import Observation

@MainActor
@Observable
final class ExploreNotificationsViewModel {
    var notifications: [ExploreNotification] = []
    var isLoading = false
    var errorMessage: String?
    var recentlyReadNotificationIds = Set<String>()

    @ObservationIgnored private let pageSize = 50

    func fetchNotifications() async -> Bool {
        guard !isLoading else { return false }

        isLoading = true
        errorMessage = nil
        recentlyReadNotificationIds = []
        defer { isLoading = false }

        do {
            let loadedNotifications = try await MerianNetworkClient.shared.getExploreNotifications(limit: pageSize, offset: 0)
            notifications = loadedNotifications

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
            errorMessage = ExploreErrorFormatter.message(for: error)
            return false
        }
    }
}
