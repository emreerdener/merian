import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentRealtimeCoordinatorTests: XCTestCase {
    func testSameAccountSubscriptionIsIdempotentAndChangeSynchronizes() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(currentUserId: userId)
        let coordinator = harness.makeCoordinator()
        defer { coordinator.stopUpdates() }

        coordinator.ensureUpdates(for: userId)
        coordinator.ensureUpdates(for: userId)

        XCTAssertEqual(harness.madeUserIds, [userId])
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }

        coordinator.ensureUpdates(for: userId)
        XCTAssertEqual(harness.madeUserIds, [userId])

        harness.subscriptions[0].sendChange()
        await assertEventually {
            harness.synchronizedUserIds == [userId]
        }
    }

    func testAccountReplacementRejectsStaleChangesAndStartsNewOwner() async {
        let firstUserId = UUID()
        let secondUserId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: firstUserId
        )
        let coordinator = harness.makeCoordinator()
        defer { coordinator.stopUpdates() }

        coordinator.ensureUpdates(for: firstUserId)
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }

        harness.currentUserId = secondUserId
        coordinator.ensureUpdates(for: secondUserId)
        XCTAssertEqual(harness.madeUserIds, [firstUserId, secondUserId])
        await assertEventually {
            harness.subscriptions.last?.status == .subscribed
        }

        harness.subscriptions[0].sendChange()
        harness.subscriptions[1].sendChange()
        await assertEventually {
            harness.synchronizedUserIds == [secondUserId]
        }
        XCTAssertGreaterThanOrEqual(harness.subscriptions[0].removeCount, 1)
    }

    func testChangedCurrentUserInvalidatesSubscriptionBeforeMutation() async {
        let subscribedUserId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: subscribedUserId
        )
        let coordinator = harness.makeCoordinator()
        defer { coordinator.stopUpdates() }

        coordinator.ensureUpdates(for: subscribedUserId)
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }

        harness.currentUserId = UUID()
        harness.subscriptions[0].sendChange()
        await assertEventually {
            harness.subscriptions[0].removeCount >= 1
        }
        XCTAssertTrue(harness.synchronizedUserIds.isEmpty)
        XCTAssertTrue(harness.retryDelays.isEmpty)
    }

    func testForegroundEnsureReplacesInactiveSameAccountSubscription() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(currentUserId: userId)
        let coordinator = harness.makeCoordinator()
        defer { coordinator.stopUpdates() }

        coordinator.ensureUpdates(for: userId)
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }
        harness.subscriptions[0].status = .inactive

        coordinator.ensureUpdates(for: userId)

        XCTAssertEqual(harness.madeUserIds, [userId, userId])
        await assertEventually {
            harness.subscriptions.last?.status == .subscribed
        }
    }

    func testCompletedStreamRetriesSameAccount() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(currentUserId: userId)
        let coordinator = harness.makeCoordinator()
        defer { coordinator.stopUpdates() }

        coordinator.ensureUpdates(for: userId)
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }

        harness.subscriptions[0].finish()

        await assertEventually {
            harness.madeUserIds.count == 2
        }
        XCTAssertEqual(harness.retryDelays, [1])
        XCTAssertTrue(harness.reportedFailures.isEmpty)
    }

    func testSubscriptionFailureReportsAndRetriesSameAccount() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: userId,
            failingSubscriptionIndexes: [0]
        )
        let coordinator = harness.makeCoordinator()
        defer { coordinator.stopUpdates() }

        coordinator.ensureUpdates(for: userId)

        await assertEventually {
            harness.madeUserIds.count == 2
        }
        XCTAssertEqual(harness.retryDelays, [1])
        XCTAssertEqual(harness.reportedFailures.count, 1)
    }

    func testRepeatedFailuresUseBoundedExponentialBackoff() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: userId,
            failingSubscriptionIndexes: Set(0 ... 5)
        )
        let coordinator = harness.makeCoordinator()
        defer { coordinator.stopUpdates() }

        coordinator.ensureUpdates(for: userId)

        await assertEventually {
            harness.madeUserIds.count == 7
        }
        XCTAssertEqual(harness.retryDelays, [1, 2, 4, 8, 16, 30])
        XCTAssertEqual(harness.reportedFailures.count, 6)
    }

    func testStopCancelsPendingRetry() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: userId,
            failingSubscriptionIndexes: [0],
            retriesImmediately: false
        )
        let coordinator = harness.makeCoordinator()

        coordinator.ensureUpdates(for: userId)
        await assertEventually {
            harness.retryDelays == [1]
        }

        harness.currentUserId = nil
        coordinator.ensureUpdates(for: nil)
        await drainTasks()

        XCTAssertEqual(harness.madeUserIds, [userId])
    }

    func testStopRemovesActiveSubscriptionExactlyOnce() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(currentUserId: userId)
        let coordinator = harness.makeCoordinator()

        coordinator.ensureUpdates(for: userId)
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }

        coordinator.stopUpdates()

        await assertEventually {
            harness.subscriptions[0].removeCount == 1
        }
        await drainTasks()
        XCTAssertEqual(harness.subscriptions[0].removeCount, 1)
    }

    func testTeardownDrainWaitsForCancellationUncooperativeRemoval() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: userId,
            removalWaitsForRelease: true
        )
        let coordinator = harness.makeCoordinator()

        coordinator.ensureUpdates(for: userId)
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }

        coordinator.stopUpdates()
        await assertEventually {
            harness.subscriptions[0].isRemovalStarted
        }

        let drainStarted = expectation(description: "Teardown drain started")
        let drainFinished = expectation(description: "Teardown drain finished")
        var didFinishDrain = false
        let drain = Task { @MainActor in
            drainStarted.fulfill()
            await coordinator.awaitTeardown()
            didFinishDrain = true
            drainFinished.fulfill()
        }
        await fulfillment(of: [drainStarted], timeout: 1)

        XCTAssertFalse(didFinishDrain)
        XCTAssertEqual(harness.subscriptions[0].removeCount, 1)

        harness.subscriptions[0].releaseRemoval()
        await fulfillment(of: [drainFinished], timeout: 1)
        await drain.value

        XCTAssertTrue(didFinishDrain)
        XCTAssertEqual(harness.subscriptions[0].removeCount, 1)
    }

    func testAuthTransitionDrainIncludesRealtimeTeardown() async throws {
        let userId = UUID()
        let suiteName = "merian.tests.consent-realtime-drain.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: userId,
            removalWaitsForRelease: true
        )
        let coordinator = harness.makeCoordinator()
        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            ),
            currentSDKUserIdProvider: { harness.currentUserId },
            analyticsPermissionApplier: { _, _ in },
            synchronizationOperation: { _, _ in },
            realtimeCoordinator: coordinator
        )

        manager.observeSession(userId: userId)
        await assertEventually {
            harness.subscriptions.first?.status == .subscribed
        }

        manager.beginAnalyticsAccountTransition()
        let drainStarted = expectation(description: "Auth drain started")
        let drainFinished = expectation(description: "Auth drain finished")
        var didFinishDrain = false
        let drain = Task { @MainActor in
            drainStarted.fulfill()
            await manager.cancelAndAwaitAccountBoundWorkForAuthTransition()
            didFinishDrain = true
            drainFinished.fulfill()
        }
        await fulfillment(of: [drainStarted], timeout: 1)
        await assertEventually {
            harness.subscriptions[0].isRemovalStarted
        }

        XCTAssertFalse(didFinishDrain)
        XCTAssertTrue(manager.isAnalyticsSuppressedForAccountTransition)

        harness.subscriptions[0].releaseRemoval()
        await fulfillment(of: [drainFinished], timeout: 1)
        await drain.value

        XCTAssertTrue(didFinishDrain)
        XCTAssertEqual(harness.subscriptions[0].removeCount, 1)
    }

    func testDeinitializationInitiatesRemovalWhenListenerIgnoresCancellation() async {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: userId,
            nextChangeWaitsForRemoval: true
        )
        var coordinator: ConsentRealtimeCoordinator? = harness.makeCoordinator()
        weak let weakCoordinator = coordinator

        coordinator?.ensureUpdates(for: userId)
        await assertEventually {
            harness.subscriptions.first?.isWaitingForRemoval == true
        }

        coordinator = nil

        await assertEventually {
            weakCoordinator == nil
                && harness.subscriptions[0].removeCount == 1
        }
    }

    func testDisabledLivePolicyDoesNotCreateSubscription() {
        let userId = UUID()
        let harness = ConsentRealtimeCoordinatorHarness(
            currentUserId: userId,
            isEnabled: false
        )
        let coordinator = harness.makeCoordinator()

        coordinator.ensureUpdates(for: userId)

        XCTAssertTrue(harness.madeUserIds.isEmpty)
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0 ..< 200 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func assertEventually(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let fulfilled = await eventually(condition)
        XCTAssertTrue(fulfilled, file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }
}

@MainActor
private final class ConsentRealtimeCoordinatorHarness {
    var currentUserId: UUID?
    var madeUserIds: [UUID] = []
    var subscriptions: [ControlledConsentRealtimeSubscription] = []
    var synchronizedUserIds: [UUID] = []
    var retryDelays: [Double] = []
    var reportedFailures: [Error] = []

    private let failingSubscriptionIndexes: Set<Int>
    private let retriesImmediately: Bool
    private let isEnabled: Bool
    private let nextChangeWaitsForRemoval: Bool
    private let removalWaitsForRelease: Bool

    init(
        currentUserId: UUID?,
        failingSubscriptionIndexes: Set<Int> = [],
        retriesImmediately: Bool = true,
        isEnabled: Bool = true,
        nextChangeWaitsForRemoval: Bool = false,
        removalWaitsForRelease: Bool = false
    ) {
        self.currentUserId = currentUserId
        self.failingSubscriptionIndexes = failingSubscriptionIndexes
        self.retriesImmediately = retriesImmediately
        self.isEnabled = isEnabled
        self.nextChangeWaitsForRemoval = nextChangeWaitsForRemoval
        self.removalWaitsForRelease = removalWaitsForRelease
    }

    func makeCoordinator() -> ConsentRealtimeCoordinator {
        let coordinator = ConsentRealtimeCoordinator(dependencies: .init(
            isEnabled: {
                self.isEnabled
            },
            makeSubscription: { userId in
                let index = self.subscriptions.count
                let subscription = ControlledConsentRealtimeSubscription(
                    failsOnSubscribe: self.failingSubscriptionIndexes
                        .contains(index),
                    nextChangeWaitsForRemoval: self.nextChangeWaitsForRemoval,
                    removalWaitsForRelease: self.removalWaitsForRelease
                )
                self.madeUserIds.append(userId)
                self.subscriptions.append(subscription)
                return subscription.value
            },
            sleep: { delay in
                self.retryDelays.append(delay)
                guard !self.retriesImmediately else { return }
                try await Task.sleep(for: .seconds(60))
            },
            reportFailure: { error in
                self.reportedFailures.append(error)
            }
        ))
        coordinator.setHandlers(
            currentUserIdProvider: {
                self.currentUserId
            },
            synchronizationHandler: { userId in
                self.synchronizedUserIds.append(userId)
            }
        )
        return coordinator
    }
}

@MainActor
private final class ControlledConsentRealtimeSubscription {
    enum Failure: Error {
        case subscriptionFailed
    }

    var status: ConsentRealtimeCoordinator.SubscriptionStatus = .subscribing
    private(set) var removeCount = 0
    private(set) var isWaitingForRemoval = false
    private(set) var isRemovalStarted = false

    private let failsOnSubscribe: Bool
    private let nextChangeWaitsForRemoval: Bool
    private let removalWaitsForRelease: Bool
    private let continuation: AsyncStream<Void>.Continuation
    private var changes: AsyncStream<Void>.Iterator
    private var removalContinuation: CheckedContinuation<Bool, Never>?
    private var removalReleaseContinuation: CheckedContinuation<Void, Never>?

    init(
        failsOnSubscribe: Bool,
        nextChangeWaitsForRemoval: Bool,
        removalWaitsForRelease: Bool
    ) {
        self.failsOnSubscribe = failsOnSubscribe
        self.nextChangeWaitsForRemoval = nextChangeWaitsForRemoval
        self.removalWaitsForRelease = removalWaitsForRelease
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.continuation = continuation
        changes = stream.makeAsyncIterator()
    }

    var value: ConsentRealtimeCoordinator.Subscription {
        ConsentRealtimeCoordinator.Subscription(
            status: {
                self.status
            },
            subscribe: {
                if self.failsOnSubscribe {
                    self.status = .inactive
                    throw Failure.subscriptionFailed
                }
                self.status = .subscribed
            },
            nextChange: {
                if self.nextChangeWaitsForRemoval {
                    self.isWaitingForRemoval = true
                    return await withCheckedContinuation { continuation in
                        self.removalContinuation = continuation
                    }
                }
                var iterator = self.changes
                let change: Void? = await iterator.next()
                self.changes = iterator
                return change != nil
            },
            remove: {
                self.removeCount += 1
                self.isRemovalStarted = true
                if self.removalWaitsForRelease {
                    await withCheckedContinuation { continuation in
                        self.removalReleaseContinuation = continuation
                    }
                }
                self.status = .inactive
                self.continuation.finish()
                self.removalContinuation?.resume(returning: false)
                self.removalContinuation = nil
            }
        )
    }

    func sendChange() {
        continuation.yield(())
    }

    func finish() {
        status = .inactive
        continuation.finish()
    }

    func releaseRemoval() {
        removalReleaseContinuation?.resume()
        removalReleaseContinuation = nil
    }
}
