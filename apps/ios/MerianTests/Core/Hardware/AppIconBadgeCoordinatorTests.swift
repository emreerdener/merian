import Foundation
@testable import Merian
import Testing

@MainActor
@Suite(
    "App Icon Badge Coordinator",
    .serialized,
    .sharedProcessState(.appIconBadgeCoordinator)
)
struct AppIconBadgeCoordinatorTests {
    init() {
        AppIconBadgeCoordinator.resetAccountState()
    }

    @Test func accountResetRejectsAnAdmittedUnreadCountResult() async {
        let loader = SuspendedUnreadCountLoader()
        AppIconBadgeCoordinator.setExploreUnreadNotificationCount(4)

        let refreshTask = Task { @MainActor in
            await AppIconBadgeCoordinator
                .refreshExploreUnreadNotificationCount(
                    force: true,
                    loadUnreadCount: { await loader.load() }
                )
        }
        await loader.waitUntilStarted()

        AppIconBadgeCoordinator.resetAccountState()
        await loader.resume(returning: 9)

        #expect(await refreshTask.value == nil)
        #expect(AppIconBadgeCoordinator.exploreUnreadNotificationCount == 0)
        #expect(UserDefaults.standard.object(
            forKey: UserDefaultsKeys.exploreUnreadNotificationBadgeCount
        ) == nil)
    }
}

private actor SuspendedUnreadCountLoader {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<Int, Never>?

    func load() async -> Int {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume(returning value: Int) {
        resultContinuation?.resume(returning: value)
        resultContinuation = nil
    }
}
