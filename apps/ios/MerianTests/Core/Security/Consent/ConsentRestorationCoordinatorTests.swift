import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentRestorationCoordinatorTests: XCTestCase {
    func testDuplicateSessionObservationPreservesRetryAndManualRetryResetsIt() {
        let userId = UUID()
        var context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 7,
            observedUserId: userId,
            sdkUserId: userId,
            hasCurrentRequiredConsent: false
        )
        var publishedState = ConsentManager.RequiredConsentRestorationState
            .awaitingInitialSession
        var reportedFailures = 0
        let coordinator = makeCoordinator(
            context: { context },
            stateChange: { publishedState = $0 },
            failure: { _ in reportedFailures += 1 }
        )

        XCTAssertFalse(coordinator.observeSession(
            previousUserId: nil,
            userId: userId,
            hasCurrentRequiredConsent: false
        ))
        XCTAssertEqual(publishedState, .reconciling(userId: userId))

        coordinator.handleSynchronizationFailure(
            RequiredConsentSynchronizationStubError.unavailable,
            for: userId,
            generation: 7
        )
        XCTAssertEqual(
            publishedState,
            .waitingToRetry(userId: userId, attempt: 1)
        )
        XCTAssertEqual(reportedFailures, 1)

        XCTAssertTrue(coordinator.observeSession(
            previousUserId: userId,
            userId: userId,
            hasCurrentRequiredConsent: false
        ))
        XCTAssertEqual(
            publishedState,
            .waitingToRetry(userId: userId, attempt: 1)
        )

        XCTAssertTrue(coordinator.requestManualRetry())
        XCTAssertEqual(publishedState, .reconciling(userId: userId))
        XCTAssertFalse(coordinator.canRetry)

        context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 7,
            observedUserId: userId,
            sdkUserId: UUID(),
            hasCurrentRequiredConsent: false
        )
        coordinator.handleSynchronizationFailure(
            RequiredConsentSynchronizationStubError.unavailable,
            for: userId,
            generation: 7
        )
        XCTAssertEqual(publishedState, .reconciling(userId: userId))
        XCTAssertEqual(reportedFailures, 1)
    }

    func testFailureBudgetTransitionsToExplicitRetry() {
        let userId = UUID()
        let context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 3,
            observedUserId: userId,
            sdkUserId: userId,
            hasCurrentRequiredConsent: false
        )
        var publishedState = ConsentManager.RequiredConsentRestorationState
            .awaitingInitialSession
        var reportedFailures = 0
        let coordinator = makeCoordinator(
            context: { context },
            stateChange: { publishedState = $0 },
            failure: { _ in reportedFailures += 1 }
        )
        coordinator.beginReconciliation(for: userId)

        for attempt in 1...RequiredConsentRestorationCoordinator
            .maximumAutomaticRetries {
            coordinator.handleSynchronizationFailure(
                RequiredConsentSynchronizationStubError.unavailable,
                for: userId,
                generation: 3
            )
            XCTAssertEqual(
                publishedState,
                .waitingToRetry(userId: userId, attempt: attempt)
            )
            XCTAssertTrue(coordinator.beginRetry(
                for: userId,
                generation: 3,
                attempt: attempt
            ))
        }

        coordinator.handleSynchronizationFailure(
            RequiredConsentSynchronizationStubError.unavailable,
            for: userId,
            generation: 3
        )

        XCTAssertEqual(publishedState, .retryRequired(userId: userId))
        XCTAssertTrue(coordinator.canRetry)
        XCTAssertEqual(
            reportedFailures,
            RequiredConsentRestorationCoordinator.maximumAutomaticRetries + 1
        )
    }

    func testCancelledUncooperativeRetryCannotCrossAccountReplacement() async {
        let firstUserId = UUID()
        let secondUserId = UUID()
        let retryStarted = expectation(description: "Retry sleep started")
        let retryResumed = expectation(description: "Retry sleep resumed")
        let drainStarted = expectation(description: "Cancellation drain started")
        let drainFinished = expectation(description: "Cancellation drain finished")
        var context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 1,
            observedUserId: firstUserId,
            sdkUserId: firstUserId,
            hasCurrentRequiredConsent: false
        )
        var publishedState = ConsentManager.RequiredConsentRestorationState
            .awaitingInitialSession
        var synchronizationCount = 0
        let sleepProbe = RequiredConsentRetrySleepProbe(
            didStart: { _ in retryStarted.fulfill() },
            didResume: { _ in retryResumed.fulfill() }
        )
        let coordinator = makeCoordinator(
            context: { context },
            stateChange: { publishedState = $0 },
            synchronize: { synchronizationCount += 1 },
            sleepProbe: sleepProbe
        )
        coordinator.beginReconciliation(for: firstUserId)
        coordinator.handleSynchronizationFailure(
            RequiredConsentSynchronizationStubError.unavailable,
            for: firstUserId,
            generation: 1
        )
        await fulfillment(of: [retryStarted], timeout: 1)

        context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 2,
            observedUserId: firstUserId,
            sdkUserId: secondUserId,
            hasCurrentRequiredConsent: false
        )
        let cancelledWork = coordinator.invalidate(
            currentUserId: firstUserId,
            hasCurrentRequiredConsent: false
        )
        var didFinishDrain = false
        let drainTask = Task { @MainActor in
            drainStarted.fulfill()
            await cancelledWork.wait()
            didFinishDrain = true
            drainFinished.fulfill()
        }
        await fulfillment(of: [drainStarted], timeout: 1)
        XCTAssertFalse(didFinishDrain)

        context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 2,
            observedUserId: secondUserId,
            sdkUserId: secondUserId,
            hasCurrentRequiredConsent: false
        )
        XCTAssertFalse(coordinator.observeSession(
            previousUserId: firstUserId,
            userId: secondUserId,
            hasCurrentRequiredConsent: false
        ))

        sleepProbe.resumeNext()
        await fulfillment(
            of: [retryResumed, drainFinished],
            timeout: 1
        )
        await drainTask.value

        XCTAssertEqual(sleepProbe.resumedCancellationStates, [true])
        XCTAssertEqual(synchronizationCount, 0)
        XCTAssertEqual(publishedState, .reconciling(userId: secondUserId))
    }

    func testCancelledRetryCannotReenterAfterManualAttemptNumberReuse() async {
        let userId = UUID()
        let firstRetryStarted = expectation(description: "First retry started")
        let replacementRetryStarted = expectation(
            description: "Replacement retry started"
        )
        let firstRetryResumed = expectation(description: "First retry resumed")
        let replacementRetryResumed = expectation(
            description: "Replacement retry resumed"
        )
        var context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 9,
            observedUserId: userId,
            sdkUserId: userId,
            hasCurrentRequiredConsent: false
        )
        var publishedState = ConsentManager.RequiredConsentRestorationState
            .awaitingInitialSession
        var synchronizationCount = 0
        let sleepProbe = RequiredConsentRetrySleepProbe(
            didStart: { count in
                if count == 1 {
                    firstRetryStarted.fulfill()
                } else if count == 2 {
                    replacementRetryStarted.fulfill()
                }
            },
            didResume: { count in
                if count == 1 {
                    firstRetryResumed.fulfill()
                } else if count == 2 {
                    replacementRetryResumed.fulfill()
                }
            }
        )
        let coordinator = makeCoordinator(
            context: { context },
            stateChange: { publishedState = $0 },
            synchronize: { synchronizationCount += 1 },
            sleepProbe: sleepProbe
        )
        coordinator.beginReconciliation(for: userId)
        coordinator.handleSynchronizationFailure(
            RequiredConsentSynchronizationStubError.unavailable,
            for: userId,
            generation: 9
        )
        await fulfillment(of: [firstRetryStarted], timeout: 1)

        XCTAssertTrue(coordinator.requestManualRetry())
        coordinator.handleSynchronizationFailure(
            RequiredConsentSynchronizationStubError.unavailable,
            for: userId,
            generation: 9
        )
        await fulfillment(of: [replacementRetryStarted], timeout: 1)
        XCTAssertEqual(
            publishedState,
            .waitingToRetry(userId: userId, attempt: 1)
        )

        sleepProbe.resumeNext()
        await fulfillment(of: [firstRetryResumed], timeout: 1)

        XCTAssertEqual(sleepProbe.resumedCancellationStates, [true])
        XCTAssertEqual(synchronizationCount, 0)
        XCTAssertEqual(
            publishedState,
            .waitingToRetry(userId: userId, attempt: 1)
        )

        context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 10,
            observedUserId: userId,
            sdkUserId: userId,
            hasCurrentRequiredConsent: false
        )
        let cancelledWork = coordinator.invalidate(
            currentUserId: userId,
            hasCurrentRequiredConsent: false
        )
        sleepProbe.resumeNext()
        await fulfillment(of: [replacementRetryResumed], timeout: 1)
        await cancelledWork.wait()

        XCTAssertEqual(sleepProbe.resumedCancellationStates, [true, true])
        XCTAssertEqual(synchronizationCount, 0)
        XCTAssertEqual(publishedState, .reconciling(userId: userId))
    }

    func testCompletingRetryCannotClearItsReplacementTask() async {
        let userId = UUID()
        let firstRetryStarted = expectation(description: "First retry started")
        let replacementRetryStarted = expectation(
            description: "Replacement retry started"
        )
        let retriesResumed = expectation(description: "Retry sleeps resumed")
        retriesResumed.expectedFulfillmentCount = 2
        var context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 11,
            observedUserId: userId,
            sdkUserId: userId,
            hasCurrentRequiredConsent: false
        )
        var publishedState = ConsentManager.RequiredConsentRestorationState
            .awaitingInitialSession
        var synchronizationCount = 0
        let sleepProbe = RequiredConsentRetrySleepProbe(
            didStart: { count in
                if count == 1 {
                    firstRetryStarted.fulfill()
                } else if count == 2 {
                    replacementRetryStarted.fulfill()
                }
            },
            didResume: { _ in retriesResumed.fulfill() }
        )
        weak var weakCoordinator: RequiredConsentRestorationCoordinator?
        let coordinator = makeCoordinator(
            context: { context },
            stateChange: { publishedState = $0 },
            synchronize: {
                synchronizationCount += 1
                if synchronizationCount == 1 {
                    weakCoordinator?.handleSynchronizationFailure(
                        RequiredConsentSynchronizationStubError.unavailable,
                        for: userId,
                        generation: 11
                    )
                }
            },
            sleepProbe: sleepProbe
        )
        weakCoordinator = coordinator
        coordinator.beginReconciliation(for: userId)
        coordinator.handleSynchronizationFailure(
            RequiredConsentSynchronizationStubError.unavailable,
            for: userId,
            generation: 11
        )
        await fulfillment(of: [firstRetryStarted], timeout: 1)

        sleepProbe.resumeNext()
        await fulfillment(of: [replacementRetryStarted], timeout: 1)
        XCTAssertEqual(
            publishedState,
            .waitingToRetry(userId: userId, attempt: 2)
        )

        context = RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: 12,
            observedUserId: userId,
            sdkUserId: userId,
            hasCurrentRequiredConsent: false
        )
        coordinator.invalidate(
            currentUserId: userId,
            hasCurrentRequiredConsent: false
        )
        sleepProbe.resumeNext()
        await fulfillment(of: [retriesResumed], timeout: 1)

        XCTAssertEqual(sleepProbe.resumedCancellationStates, [false, true])
        XCTAssertEqual(synchronizationCount, 1)
        XCTAssertEqual(publishedState, .reconciling(userId: userId))
    }

    private func makeCoordinator(
        context: @escaping @MainActor ()
            -> RequiredConsentRestorationCoordinator.Context?,
        stateChange: @escaping @MainActor (
            ConsentManager.RequiredConsentRestorationState
        ) -> Void,
        synchronize: @escaping @MainActor () async throws -> Void = {},
        failure: @escaping @MainActor (Error) -> Void = { _ in },
        sleepProbe: RequiredConsentRetrySleepProbe? = nil
    ) -> RequiredConsentRestorationCoordinator {
        let coordinator = RequiredConsentRestorationCoordinator(
            dependencies: .init(
                shouldScheduleAutomaticRetry: { sleepProbe != nil },
                sleep: { delay in
                    guard let sleepProbe else { return }
                    await sleepProbe.sleep(delay: delay)
                }
            )
        )
        coordinator.setHandlers(
            contextProvider: context,
            stateChangeHandler: stateChange,
            synchronizationHandler: synchronize,
            failureReporter: failure
        )
        return coordinator
    }
}

@MainActor
private final class RequiredConsentRetrySleepProbe {
    private let didStart: @MainActor (Int) -> Void
    private let didResume: @MainActor (Int) -> Void
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var delays: [Double] = []
    private(set) var resumedCancellationStates: [Bool] = []

    init(
        didStart: @escaping @MainActor (Int) -> Void = { _ in },
        didResume: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.didStart = didStart
        self.didResume = didResume
    }

    func sleep(delay: Double) async {
        delays.append(delay)
        didStart(delays.count)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        resumedCancellationStates.append(Task.isCancelled)
        didResume(resumedCancellationStates.count)
    }

    func resumeNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}
