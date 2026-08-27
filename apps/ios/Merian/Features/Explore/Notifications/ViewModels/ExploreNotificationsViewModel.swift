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

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var nextCursorUpdatedAt: String?
    @ObservationIgnored private var nextCursorNotificationId: String?
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var hasReachedEnd = false
    @ObservationIgnored private var catalogGeneration = UUID()
    @ObservationIgnored private var activePaginationRequestId: UUID?
    @ObservationIgnored private var activeMarkAllRequestId: UUID?

    init(
        dependencies: Dependencies = .live,
        pageSize: Int = 50
    ) {
        self.dependencies = dependencies
        self.pageSize = pageSize
    }

    func fetchNotifications(force: Bool = false) async -> Bool {
        guard force || !isLoading else { return false }

        let generation = UUID()
        catalogGeneration = generation
        activePaginationRequestId = nil
        activeMarkAllRequestId = nil
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        recentlyReadNotificationIds = []

        defer {
            if catalogGeneration == generation {
                isLoading = false
            }
        }

        do {
            let loadedNotifications = try await dependencies.loadNotifications(
                pageSize,
                nil,
                nil
            )
            guard catalogGeneration == generation else { return false }

            notifications = visibleNotifications(loadedNotifications)
            hasLoadedOnce = true
            hasReachedEnd = loadedNotifications.count < pageSize
            updateCursor(using: loadedNotifications)

            let unreadIds = Set(loadedNotifications.filter { !$0.isRead }.map(\.id))
            guard !unreadIds.isEmpty else {
                recentlyReadNotificationIds = []
                return false
            }

            try await dependencies.markNotificationsRead()
            guard catalogGeneration == generation else { return false }

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
            guard catalogGeneration == generation else { return false }
            dependencies.reportFetchFailure(error, "sheet_load")
            errorMessage = dependencies.errorMessage(error)
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

        let generation = catalogGeneration
        let requestId = UUID()
        activePaginationRequestId = requestId
        isLoadingMore = true
        defer {
            if catalogGeneration == generation,
               activePaginationRequestId == requestId {
                isLoadingMore = false
            }
        }

        do {
            let nextPage = try await dependencies.loadNotifications(
                pageSize,
                nextCursorUpdatedAt,
                nextCursorNotificationId
            )
            guard catalogGeneration == generation,
                  activePaginationRequestId == requestId else { return }

            appendUniqueNotifications(visibleNotifications(nextPage))
            hasReachedEnd = nextPage.count < pageSize
            updateCursor(using: nextPage)
        } catch is CancellationError {
            // Absorb cancellation while the sheet is being dismissed.
        } catch let error as URLError where error.code == .cancelled {
            // Absorb URLSession cancellation.
        } catch {
            guard catalogGeneration == generation,
                  activePaginationRequestId == requestId else { return }
            dependencies.reportFetchFailure(error, "pagination")
        }
    }

    func markAllAsRead() async {
        let generation = catalogGeneration
        let requestId = UUID()
        activeMarkAllRequestId = requestId

        _ = try? await dependencies.markNotificationsRead()
        guard catalogGeneration == generation,
              activeMarkAllRequestId == requestId else { return }

        recentlyReadNotificationIds.removeAll()
        for index in notifications.indices {
            notifications[index].isRead = true
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
        guard dependencies.includesFieldTripNotifications() else {
            return page.filter { !$0.type.isFieldTripNotification }
        }
        return page
    }
}
