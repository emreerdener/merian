import Foundation
import Testing

@testable import Merian

@MainActor
struct AppIconBadgeControllerTests {
    @Test("Unread counts normalize and aggregate with unseen scans")
    func normalizedAggregateCount() {
        let probe = BadgeProbe()
        probe.hasUnseenScan = true
        let controller = probe.makeController()

        controller.setExploreUnreadNotificationCount(-3)
        #expect(probe.unreadCount == 0)
        #expect(probe.badgeCounts == [1])

        controller.setExploreUnreadNotificationCount(4)
        #expect(probe.unreadCount == 4)
        #expect(probe.badgeCounts == [1, 5])

        controller.setExploreUnreadNotificationCount(Int.max)
        #expect(probe.unreadCount == Int.max)
        #expect(probe.badgeCounts.last == Int.max)
    }

    @Test("Successful refreshes reuse their cached count for ten seconds")
    func refreshReuseWindow() async {
        let probe = BadgeProbe()
        let controller = probe.makeController()
        var loadCount = 0
        let loader: @MainActor () async throws -> Int = {
            loadCount += 1
            return loadCount * 3
        }

        #expect(
            await controller.refreshExploreUnreadNotificationCount(
                force: false,
                loadUnreadCount: loader
            ) == 3
        )
        #expect(
            await controller.refreshExploreUnreadNotificationCount(
                force: false,
                loadUnreadCount: loader
            ) == 3
        )
        #expect(loadCount == 1)

        probe.date = probe.date.addingTimeInterval(10)
        #expect(
            await controller.refreshExploreUnreadNotificationCount(
                force: false,
                loadUnreadCount: loader
            ) == 6
        )
        #expect(loadCount == 2)

        probe.date = probe.date.addingTimeInterval(-20)
        #expect(
            await controller.refreshExploreUnreadNotificationCount(
                force: false,
                loadUnreadCount: loader
            ) == 9
        )
        #expect(loadCount == 3)
    }

    @Test("Concurrent refresh callers share one load")
    func concurrentRefreshesCoalesce() async {
        let probe = BadgeProbe()
        let controller = probe.makeController()
        let gate = NotificationAsyncGate()
        var loadCount = 0
        let loader: @MainActor () async throws -> Int = {
            loadCount += 1
            await gate.suspend()
            return 7
        }

        let first = Task {
            await controller.refreshExploreUnreadNotificationCount(
                force: true,
                loadUnreadCount: loader
            )
        }
        await waitUntil { gate.entryCount == 1 }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return await controller.refreshExploreUnreadNotificationCount(
                force: true,
                loadUnreadCount: loader
            )
        }
        await waitUntil { secondStarted }
        #expect(loadCount == 1)
        gate.resume()

        #expect(await first.value == 7)
        #expect(await second.value == 7)
        #expect(loadCount == 1)
        #expect(probe.unreadCount == 7)
    }

    @Test("Account reset rejects an admitted unread result")
    func accountResetRejectsStaleResult() async {
        let probe = BadgeProbe()
        probe.unreadCount = 4
        let controller = probe.makeController()
        let gate = NotificationAsyncGate()
        let refresh = Task {
            await controller.refreshExploreUnreadNotificationCount(
                force: true,
                loadUnreadCount: {
                    await gate.suspend()
                    return 9
                }
            )
        }
        await waitUntil { gate.entryCount == 1 }

        controller.resetAccountState()
        gate.resume()

        #expect(await refresh.value == nil)
        #expect(probe.unreadCount == nil)
        #expect(controller.exploreUnreadNotificationCount == 0)
        #expect(probe.badgeCounts.last == 0)
    }

    @Test("A local unread mutation rejects an admitted remote result")
    func localMutationRejectsStaleResult() async {
        let probe = BadgeProbe()
        probe.unreadCount = 4
        let controller = probe.makeController()
        let gate = NotificationAsyncGate()
        let refresh = Task {
            await controller.refreshExploreUnreadNotificationCount(
                force: true,
                loadUnreadCount: {
                    await gate.suspend()
                    return 9
                }
            )
        }
        await waitUntil { gate.entryCount == 1 }

        controller.clearExploreUnreadNotificationCount()
        gate.resume()

        #expect(await refresh.value == nil)
        #expect(probe.unreadCount == 0)
        #expect(controller.exploreUnreadNotificationCount == 0)
        #expect(probe.badgeCounts.last == 0)
    }

    @Test("Refresh failure preserves state and remains retryable")
    func refreshFailurePreservesState() async {
        let probe = BadgeProbe()
        probe.unreadCount = 4
        let controller = probe.makeController()
        var loadCount = 0

        let failed = await controller.refreshExploreUnreadNotificationCount(
            force: false,
            loadUnreadCount: {
                loadCount += 1
                throw NotificationTestError.expected
            }
        )
        let recovered = await controller.refreshExploreUnreadNotificationCount(
            force: false,
            loadUnreadCount: {
                loadCount += 1
                return 8
            }
        )

        #expect(failed == nil)
        #expect(recovered == 8)
        #expect(loadCount == 2)
        #expect(probe.errors.count == 1)
        #expect(probe.unreadCount == 8)
    }
}

@MainActor
private final class BadgeProbe {
    var unreadCount: Int?
    var hasUnseenScan = false
    var badgeCounts: [Int] = []
    var date = Date(timeIntervalSince1970: 1_000)
    var errors: [any Error] = []

    func makeController() -> AppIconBadgeController {
        AppIconBadgeController(
            dependencies: AppIconBadgeDependencies(
                readExploreUnreadCount: { self.unreadCount ?? 0 },
                writeExploreUnreadCount: { self.unreadCount = $0 },
                removeExploreUnreadCount: { self.unreadCount = nil },
                hasUnseenScan: { self.hasUnseenScan },
                setBadgeCount: { self.badgeCounts.append($0) },
                now: { self.date },
                reportRefreshFailure: { self.errors.append($0) }
            )
        )
    }
}
