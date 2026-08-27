import XCTest

@testable import Merian

@MainActor
final class ExploreNotificationsViewModelTests: XCTestCase {
    func testInitialFetchMarksUnreadRowsOnlyAfterReadEndpointSucceeds() async {
        let unread = ExploreNotificationsTestFixtures.notification(id: "unread")
        let alreadyRead = ExploreNotificationsTestFixtures.notification(
            id: "already-read",
            isRead: true
        )
        var requestedLimit: Int?
        var markReadCount = 0
        let viewModel = ExploreNotificationsViewModel(
            dependencies: ExploreNotificationsTestFixtures.catalogDependencies(
                loadNotifications: { limit, beforeUpdatedAt, beforeNotificationId in
                    requestedLimit = limit
                    XCTAssertNil(beforeUpdatedAt)
                    XCTAssertNil(beforeNotificationId)
                    return [unread, alreadyRead]
                },
                markNotificationsRead: {
                    markReadCount += 1
                }
            ),
            pageSize: 3
        )

        let didClearUnread = await viewModel.fetchNotifications()

        XCTAssertTrue(didClearUnread)
        XCTAssertEqual(requestedLimit, 3)
        XCTAssertEqual(markReadCount, 1)
        XCTAssertEqual(viewModel.notifications.map(\.id), ["unread", "already-read"])
        XCTAssertTrue(viewModel.notifications.allSatisfy(\.isRead))
        XCTAssertEqual(viewModel.recentlyReadNotificationIds, ["unread"])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testReadEndpointFailureRetainsLoadedRowsAndSurfacesLoadError() async {
        let unread = ExploreNotificationsTestFixtures.notification(id: "unread")
        var failureContexts: [String] = []
        let viewModel = ExploreNotificationsViewModel(
            dependencies: ExploreNotificationsTestFixtures.catalogDependencies(
                loadNotifications: { _, _, _ in [unread] },
                markNotificationsRead: {
                    throw ExploreNotificationsTestFixtures.StubError.failed
                },
                reportFetchFailure: { _, context in
                    failureContexts.append(context)
                }
            )
        )

        let didClearUnread = await viewModel.fetchNotifications()

        XCTAssertFalse(didClearUnread)
        XCTAssertEqual(viewModel.notifications.map(\.id), ["unread"])
        XCTAssertFalse(viewModel.notifications[0].isRead)
        XCTAssertTrue(viewModel.recentlyReadNotificationIds.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Stub error")
        XCTAssertEqual(failureContexts, ["sheet_load"])
        XCTAssertFalse(viewModel.isLoading)
    }

    func testRefreshSupersedesPaginationAndDiscardsItsStalePage() async {
        let first = ExploreNotificationsTestFixtures.notification(id: "first", isRead: true)
        let second = ExploreNotificationsTestFixtures.notification(
            id: "second",
            isRead: true,
            updatedAt: "2026-08-01T11:00:00Z"
        )
        let stale = ExploreNotificationsTestFixtures.notification(id: "stale", isRead: true)
        let refreshed = ExploreNotificationsTestFixtures.notification(id: "refreshed", isRead: true)
        let paginationStarted = expectation(description: "Pagination started")
        var firstPageLoadCount = 0
        var pendingPagination: CheckedContinuation<[ExploreNotification], any Error>?

        let viewModel = ExploreNotificationsViewModel(
            dependencies: ExploreNotificationsTestFixtures.catalogDependencies(
                loadNotifications: { _, beforeUpdatedAt, beforeNotificationId in
                    if beforeUpdatedAt != nil || beforeNotificationId != nil {
                        return try await withCheckedThrowingContinuation { continuation in
                            pendingPagination = continuation
                            paginationStarted.fulfill()
                        }
                    }

                    firstPageLoadCount += 1
                    return firstPageLoadCount == 1 ? [first, second] : [refreshed]
                }
            ),
            pageSize: 2
        )

        _ = await viewModel.fetchNotifications()
        let paginationTask = Task {
            await viewModel.loadMoreIfNeeded(currentNotification: second)
        }
        await fulfillment(of: [paginationStarted], timeout: 1)

        let didClearUnread = await viewModel.fetchNotifications(force: true)
        pendingPagination?.resume(returning: [stale])
        _ = await paginationTask.value

        XCTAssertFalse(didClearUnread)
        XCTAssertEqual(firstPageLoadCount, 2)
        XCTAssertEqual(viewModel.notifications.map(\.id), ["refreshed"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testPaginationFailureLeavesLoadedRowsUsable() async {
        let first = ExploreNotificationsTestFixtures.notification(id: "first", isRead: true)
        let second = ExploreNotificationsTestFixtures.notification(id: "second", isRead: true)
        var failureContexts: [String] = []
        let viewModel = ExploreNotificationsViewModel(
            dependencies: ExploreNotificationsTestFixtures.catalogDependencies(
                loadNotifications: { _, beforeUpdatedAt, _ in
                    if beforeUpdatedAt == nil {
                        return [first, second]
                    }
                    throw ExploreNotificationsTestFixtures.StubError.failed
                },
                reportFetchFailure: { _, context in
                    failureContexts.append(context)
                }
            ),
            pageSize: 2
        )

        _ = await viewModel.fetchNotifications()
        await viewModel.loadMoreIfNeeded(currentNotification: second)

        XCTAssertEqual(viewModel.notifications.map(\.id), ["first", "second"])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(failureContexts, ["pagination"])
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testFailedRefreshPreservesLastSuccessfulPaginationCursor() async {
        let first = ExploreNotificationsTestFixtures.notification(id: "first", isRead: true)
        let cursor = ExploreNotificationsTestFixtures.notification(
            id: "cursor",
            isRead: true,
            updatedAt: "2026-08-01T11:00:00Z"
        )
        let older = ExploreNotificationsTestFixtures.notification(
            id: "older",
            isRead: true,
            updatedAt: "2026-08-01T10:00:00Z"
        )
        var firstPageLoadCount = 0
        var paginationCursor: String?
        let viewModel = ExploreNotificationsViewModel(
            dependencies: ExploreNotificationsTestFixtures.catalogDependencies(
                loadNotifications: { _, beforeUpdatedAt, beforeNotificationId in
                    if beforeUpdatedAt != nil || beforeNotificationId != nil {
                        paginationCursor = beforeNotificationId
                        return [older]
                    }

                    firstPageLoadCount += 1
                    if firstPageLoadCount == 1 {
                        return [first, cursor]
                    }
                    throw ExploreNotificationsTestFixtures.StubError.failed
                }
            ),
            pageSize: 2
        )

        _ = await viewModel.fetchNotifications()
        _ = await viewModel.fetchNotifications(force: true)
        await viewModel.loadMoreIfNeeded(currentNotification: cursor)

        XCTAssertEqual(firstPageLoadCount, 2)
        XCTAssertEqual(paginationCursor, "cursor")
        XCTAssertEqual(viewModel.notifications.map(\.id), ["first", "cursor", "older"])
        XCTAssertEqual(viewModel.errorMessage, "Stub error")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testFieldTripRowsUseInjectedAvailabilityPolicy() async {
        let ordinary = ExploreNotificationsTestFixtures.notification(id: "ordinary", isRead: true)
        let fieldTrip = ExploreNotificationsTestFixtures.notification(
            id: "field-trip",
            type: .fieldTripComment,
            postId: nil,
            fieldTripPublicationId: "publication-1",
            isRead: true
        )
        let viewModel = ExploreNotificationsViewModel(
            dependencies: ExploreNotificationsTestFixtures.catalogDependencies(
                loadNotifications: { _, _, _ in [ordinary, fieldTrip] },
                includesFieldTripNotifications: { false }
            )
        )

        _ = await viewModel.fetchNotifications()

        XCTAssertEqual(viewModel.notifications.map(\.id), ["ordinary"])
    }

    func testMarkAllCompletionCannotMutateRefreshedRows() async {
        let initial = ExploreNotificationsTestFixtures.notification(id: "initial", isRead: false)
        let refreshed = ExploreNotificationsTestFixtures.notification(id: "refreshed", isRead: false)
        let markAllStarted = expectation(description: "Mark all started")
        var loadCount = 0
        var markCount = 0
        var pendingMarkAll: CheckedContinuation<Void, any Error>?
        let viewModel = ExploreNotificationsViewModel(
            dependencies: ExploreNotificationsTestFixtures.catalogDependencies(
                loadNotifications: { _, _, _ in
                    loadCount += 1
                    return loadCount == 1 ? [initial] : [refreshed]
                },
                markNotificationsRead: {
                    markCount += 1
                    if markCount == 2 {
                        return try await withCheckedThrowingContinuation { continuation in
                            pendingMarkAll = continuation
                            markAllStarted.fulfill()
                        }
                    }
                }
            )
        )

        _ = await viewModel.fetchNotifications()
        let markAllTask = Task { await viewModel.markAllAsRead() }
        await fulfillment(of: [markAllStarted], timeout: 1)

        _ = await viewModel.fetchNotifications(force: true)
        pendingMarkAll?.resume()
        _ = await markAllTask.value

        XCTAssertEqual(viewModel.notifications.map(\.id), ["refreshed"])
        XCTAssertTrue(viewModel.notifications[0].isRead)
        XCTAssertEqual(viewModel.recentlyReadNotificationIds, ["refreshed"])
    }
}
