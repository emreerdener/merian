import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Capture navigation view model")
struct CaptureNavigationViewModelTests {
    @Test("Auth readiness defers badge requests and retries when the session is usable")
    func readinessDefersThenLoadsBadges() async {
        let spy = CaptureNavigationSpy()
        let viewModel = CaptureNavigationViewModel(dependencies: CaptureNavigationDependencies(
            loadBadgeSnapshot: { value in
                spy.requestedLastSeenValues.append(value)
                return CaptureNavigationBadgeSnapshot(hasUnseenExternalPost: true, unreadNotificationCount: 1)
            },
            setHasUnseenExplorePost: { spy.unseenPostValues.append($0) },
            performRouteFeedback: {}
        ))
        await viewModel.refreshBadges(lastSeenSharedAt: "pending", isAccountWorkAllowed: false)
        #expect(spy.requestedLastSeenValues.isEmpty)
        #expect(spy.unseenPostValues == [false])
        await viewModel.refreshBadges(lastSeenSharedAt: "ready", isAccountWorkAllowed: true)
        #expect(spy.requestedLastSeenValues == ["ready"])
        #expect(spy.unseenPostValues == [false, true])
    }

    @Test("Closing account readiness fences a suspended badge result")
    func readinessClosureFencesPendingRefresh() async {
        let gate = CaptureNavigationBadgeGate()
        let spy = CaptureNavigationSpy()
        let viewModel = CaptureNavigationViewModel(dependencies: CaptureNavigationDependencies(
            loadBadgeSnapshot: { await gate.load(key: $0) },
            setHasUnseenExplorePost: { spy.unseenPostValues.append($0) },
            performRouteFeedback: {}
        ))
        let pending = Task {
            await viewModel.refreshBadges(lastSeenSharedAt: "old-session", isAccountWorkAllowed: true)
        }
        await gate.waitUntilStarted(key: "old-session")
        await viewModel.refreshBadges(lastSeenSharedAt: "transition", isAccountWorkAllowed: false)
        await gate.resume(key: "old-session", with: CaptureNavigationBadgeSnapshot(
            hasUnseenExternalPost: true, unreadNotificationCount: 2
        ))
        await pending.value
        #expect(spy.unseenPostValues == [false])
        #expect(!viewModel.hasUnreadExploreNotifications)
    }

    @Test("Account replacement or readiness closure clears previously published badges")
    func accountBoundaryClearsPublishedBadges() async {
        for closesReadiness in [false, true] {
            let firstOwner = UUID()
            let nextOwner = closesReadiness ? firstOwner : UUID()
            let spy = CaptureNavigationSpy()
            spy.snapshots = [
                CaptureNavigationBadgeSnapshot(hasUnseenExternalPost: true, unreadNotificationCount: 1),
                CaptureNavigationBadgeSnapshot(hasUnseenExternalPost: false, unreadNotificationCount: nil)
            ]
            let viewModel = CaptureNavigationViewModel(dependencies: CaptureNavigationDependencies(
                loadBadgeSnapshot: { _ in spy.nextSnapshot() },
                setHasUnseenExplorePost: { spy.unseenPostValues.append($0) },
                performRouteFeedback: {}
            ))
            await viewModel.refreshBadges(lastSeenSharedAt: "first", userID: firstOwner)
            #expect(viewModel.hasUnreadExploreNotifications)
            #expect(spy.unseenPostValues.last == true)
            if closesReadiness {
                await viewModel.refreshBadges(
                    lastSeenSharedAt: "closed", userID: firstOwner, isAccountWorkAllowed: false
                )
                #expect(!viewModel.hasUnreadExploreNotifications)
                #expect(spy.unseenPostValues.last == false)
                #expect(spy.snapshots.count == 1)
            }
            await viewModel.refreshBadges(lastSeenSharedAt: "next", userID: nextOwner)
            #expect(!viewModel.hasUnreadExploreNotifications)
            #expect(spy.unseenPostValues.last == false)
        }
    }

    @Test("A badge snapshot updates both Explore badge sources atomically")
    func appliesBadgeSnapshot() async {
        let spy = CaptureNavigationSpy()
        let viewModel = CaptureNavigationViewModel(
            dependencies: CaptureNavigationDependencies(
                loadBadgeSnapshot: { lastSeenSharedAt in
                    spy.requestedLastSeenValues.append(lastSeenSharedAt)
                    return CaptureNavigationBadgeSnapshot(
                        hasUnseenExternalPost: true,
                        unreadNotificationCount: 2
                    )
                },
                setHasUnseenExplorePost: {
                    spy.unseenPostValues.append($0)
                },
                performRouteFeedback: {
                    spy.feedbackCount += 1
                }
            )
        )

        await viewModel.refreshBadges(lastSeenSharedAt: "last-seen")

        #expect(spy.requestedLastSeenValues == ["last-seen"])
        #expect(spy.unseenPostValues == [true])
        #expect(viewModel.hasUnreadExploreNotifications)
    }

    @Test("An unavailable unread count preserves the last known notification badge")
    func unavailableUnreadCountPreservesState() async {
        let spy = CaptureNavigationSpy()
        spy.snapshots = [
            CaptureNavigationBadgeSnapshot(
                hasUnseenExternalPost: true,
                unreadNotificationCount: 1
            ),
            CaptureNavigationBadgeSnapshot(
                hasUnseenExternalPost: false,
                unreadNotificationCount: nil
            )
        ]
        let viewModel = CaptureNavigationViewModel(
            dependencies: CaptureNavigationDependencies(
                loadBadgeSnapshot: { _ in spy.nextSnapshot() },
                setHasUnseenExplorePost: {
                    spy.unseenPostValues.append($0)
                },
                performRouteFeedback: {}
            )
        )

        await viewModel.refreshBadges(lastSeenSharedAt: "first")
        await viewModel.refreshBadges(lastSeenSharedAt: "second")

        #expect(viewModel.hasUnreadExploreNotifications)
        #expect(spy.unseenPostValues == [true, false])
    }

    @Test("Overlapping refreshes apply only the latest snapshot")
    func latestRefreshWins() async {
        let gate = CaptureNavigationBadgeGate()
        let spy = CaptureNavigationSpy()
        let viewModel = CaptureNavigationViewModel(
            dependencies: CaptureNavigationDependencies(
                loadBadgeSnapshot: { await gate.load(key: $0) },
                setHasUnseenExplorePost: {
                    spy.unseenPostValues.append($0)
                },
                performRouteFeedback: {}
            )
        )

        let first = Task {
            await viewModel.refreshBadges(lastSeenSharedAt: "first")
        }
        await gate.waitUntilStarted(key: "first")

        let second = Task {
            await viewModel.refreshBadges(lastSeenSharedAt: "second")
        }
        await gate.waitUntilStarted(key: "second")
        await gate.resume(
            key: "second",
            with: CaptureNavigationBadgeSnapshot(
                hasUnseenExternalPost: true,
                unreadNotificationCount: 4
            )
        )
        await second.value

        await gate.resume(
            key: "first",
            with: CaptureNavigationBadgeSnapshot(
                hasUnseenExternalPost: false,
                unreadNotificationCount: 0
            )
        )
        await first.value

        #expect(spy.unseenPostValues == [true])
        #expect(viewModel.hasUnreadExploreNotifications)
    }

    @Test("Invalidation prevents a detached refresh result from mutating badges")
    func invalidationFencesPendingRefresh() async {
        let gate = CaptureNavigationBadgeGate()
        let spy = CaptureNavigationSpy()
        let viewModel = CaptureNavigationViewModel(
            dependencies: CaptureNavigationDependencies(
                loadBadgeSnapshot: { await gate.load(key: $0) },
                setHasUnseenExplorePost: {
                    spy.unseenPostValues.append($0)
                },
                performRouteFeedback: {}
            )
        )

        let refresh = Task {
            await viewModel.refreshBadges(lastSeenSharedAt: "pending")
        }
        await gate.waitUntilStarted(key: "pending")
        viewModel.invalidateRefresh()
        await gate.resume(
            key: "pending",
            with: CaptureNavigationBadgeSnapshot(
                hasUnseenExternalPost: true,
                unreadNotificationCount: 3
            )
        )
        await refresh.value

        #expect(spy.unseenPostValues.isEmpty)
        #expect(!viewModel.hasUnreadExploreNotifications)
    }

    @Test("Navigation feedback uses the injected route effect")
    func routesFeedback() {
        let spy = CaptureNavigationSpy()
        let viewModel = CaptureNavigationViewModel(
            dependencies: CaptureNavigationDependencies(
                loadBadgeSnapshot: { _ in
                    CaptureNavigationBadgeSnapshot(
                        hasUnseenExternalPost: false,
                        unreadNotificationCount: nil
                    )
                },
                setHasUnseenExplorePost: { _ in },
                performRouteFeedback: {
                    spy.feedbackCount += 1
                }
            )
        )

        viewModel.performRouteFeedback()

        #expect(spy.feedbackCount == 1)
    }
}

@MainActor
private final class CaptureNavigationSpy {
    var requestedLastSeenValues: [String] = []
    var unseenPostValues: [Bool] = []
    var feedbackCount = 0
    var snapshots: [CaptureNavigationBadgeSnapshot] = []

    func nextSnapshot() -> CaptureNavigationBadgeSnapshot {
        snapshots.removeFirst()
    }
}

private actor CaptureNavigationBadgeGate {
    private var continuations: [
        String: CheckedContinuation<CaptureNavigationBadgeSnapshot, Never>
    ] = [:]
    private var startedKeys: Set<String> = []
    private var startWaiters: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]

    func load(key: String) async -> CaptureNavigationBadgeSnapshot {
        startedKeys.insert(key)
        let waiters = startWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters {
            waiter.resume()
        }

        return await withCheckedContinuation { continuation in
            continuations[key] = continuation
        }
    }

    func waitUntilStarted(key: String) async {
        guard !startedKeys.contains(key) else { return }
        await withCheckedContinuation { continuation in
            startWaiters[key, default: []].append(continuation)
        }
    }

    func resume(
        key: String,
        with snapshot: CaptureNavigationBadgeSnapshot
    ) {
        continuations.removeValue(forKey: key)?.resume(returning: snapshot)
    }
}
