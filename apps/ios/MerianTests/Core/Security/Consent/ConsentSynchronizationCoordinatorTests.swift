import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentSynchronizationCoordinatorTests: ConsentManagerTestCase {
    func testSameAccountSynchronizationCoalescesAndReportsOneFailure() async {
        let userId = UUID()
        let gate = ConsentSynchronizationTestGate()
        var attempts = 0
        var failures = 0
        let coordinator = makeCoordinator(
            userId: userId,
            customSynchronizationOperation: { receivedUserId, generation in
                XCTAssertEqual(receivedUserId, userId)
                XCTAssertEqual(generation, 0)
                attempts += 1
                await gate.wait()
                throw StubError.unavailable
            },
            failureHandler: { error, receivedUserId, generation in
                XCTAssertTrue(error is StubError)
                XCTAssertEqual(receivedUserId, userId)
                XCTAssertEqual(generation, 0)
                failures += 1
            }
        )

        let first = Task { @MainActor in
            try await coordinator.synchronize(for: userId)
        }
        await assertEventually { gate.isWaiting }
        let second = Task { @MainActor in
            try await coordinator.synchronize(for: userId)
        }
        await drainTasks()

        XCTAssertEqual(attempts, 1)
        gate.open()
        await assertThrowsStubError(first)
        await assertThrowsStubError(second)
        XCTAssertEqual(failures, 1)
    }

    func testCancelAndAwaitDrainsTheExactActiveTask() async {
        let userId = UUID()
        var didStart = false
        var didObserveCancellation = false
        var failures = 0
        let coordinator = makeCoordinator(
            userId: userId,
            customSynchronizationOperation: { _, _ in
                didStart = true
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    didObserveCancellation = true
                    throw error
                }
            },
            failureHandler: { _, _, _ in
                failures += 1
            }
        )
        let task = Task { @MainActor in
            try await coordinator.synchronize(for: userId)
        }
        await assertEventually { didStart }

        await coordinator.cancelAndAwait()

        XCTAssertTrue(didObserveCancellation)
        XCTAssertEqual(coordinator.generation, 1)
        XCTAssertEqual(failures, 0)
        do {
            try await task.value
            XCTFail("Cancelled synchronization must not report success.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancelAndAwaitDrainsEarlierInvalidatedActiveTask() async {
        let userId = UUID()
        let gate = ConsentSynchronizationTestGate()
        var didStart = false
        var didDrain = false
        var failures = 0
        let coordinator = makeCoordinator(
            userId: userId,
            customSynchronizationOperation: { _, _ in
                didStart = true
                await gate.wait()
                try Task.checkCancellation()
            },
            failureHandler: { _, _, _ in
                failures += 1
            }
        )
        let synchronizationTask = Task { @MainActor in
            try await coordinator.synchronize(for: userId)
        }
        await assertEventually { didStart && gate.isWaiting }

        coordinator.invalidate()
        let drainTask = Task { @MainActor in
            await coordinator.cancelAndAwait()
            didDrain = true
        }
        await drainTasks()

        XCTAssertFalse(didDrain)
        gate.open()
        await drainTask.value
        XCTAssertTrue(didDrain)
        XCTAssertEqual(failures, 0)
        do {
            try await synchronizationTask.value
            XCTFail("Invalidated synchronization must not report success.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancelAndAwaitDrainsSupersededActiveTask() async throws {
        let firstUserId = UUID()
        let secondUserId = UUID()
        let gate = ConsentSynchronizationTestGate()
        var observedUserId = firstUserId
        var firstDidStart = false
        var firstDidFinish = false
        var secondDidRun = false
        var didDrain = false
        let coordinator = makeCoordinator(
            repository: ConsentLedgerRepository(
                store: FaultInjectingConsentLedgerStore()
            ),
            customSynchronizationOperation: { userId, _ in
                if userId == firstUserId {
                    firstDidStart = true
                    await gate.wait()
                    firstDidFinish = true
                    try Task.checkCancellation()
                } else {
                    XCTAssertEqual(userId, secondUserId)
                    secondDidRun = true
                }
            },
            observedUserId: { observedUserId },
            sdkUserId: { observedUserId }
        )
        let firstSynchronizationTask = Task { @MainActor in
            try await coordinator.synchronize(for: firstUserId)
        }
        await assertEventually { firstDidStart && gate.isWaiting }

        observedUserId = secondUserId
        try await coordinator.synchronize(for: secondUserId)
        XCTAssertTrue(secondDidRun)

        let drainTask = Task { @MainActor in
            await coordinator.cancelAndAwait()
            didDrain = true
        }
        await drainTasks()

        XCTAssertFalse(didDrain)
        XCTAssertFalse(firstDidFinish)
        gate.open()
        await drainTask.value
        XCTAssertTrue(firstDidFinish)
        XCTAssertTrue(didDrain)
        do {
            try await firstSynchronizationTask.value
            XCTFail("Superseded synchronization must not report success.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancelAndAwaitDrainsSupersededScheduledTask() async {
        let userId = UUID()
        let gate = ConsentSynchronizationTestGate()
        var didStart = false
        var didFinish = false
        var didDrain = false
        let coordinator = makeCoordinator(
            repository: ConsentLedgerRepository(
                store: FaultInjectingConsentLedgerStore()
            ),
            observedUserId: { userId },
            sdkUserId: { userId }
        )
        coordinator.schedule {
            didStart = true
            await gate.wait()
            didFinish = true
        }
        await assertEventually { didStart && gate.isWaiting }

        coordinator.schedule {}
        let drainTask = Task { @MainActor in
            await coordinator.cancelAndAwait()
            didDrain = true
        }
        await drainTasks()

        XCTAssertFalse(didDrain)
        XCTAssertFalse(didFinish)
        gate.open()
        await drainTask.value
        XCTAssertTrue(didFinish)
        XCTAssertTrue(didDrain)
    }

    func testInvalidatedGenerationRejectsMergeBeforePersistence() throws {
        let userId = UUID()
        var observedUserId: UUID? = userId
        var sdkUserId: UUID? = userId
        let store = FaultInjectingConsentLedgerStore()
        let repository = ConsentLedgerRepository(store: store)
        let coordinator = makeCoordinator(
            repository: repository,
            observedUserId: { observedUserId },
            sdkUserId: { sdkUserId }
        )
        coordinator.invalidate()
        observedUserId = UUID()
        sdkUserId = observedUserId

        XCTAssertThrowsError(
            try coordinator.merge(
                emptyRemoteState(),
                for: userId,
                generation: 0
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(store.operations.isEmpty)
        XCTAssertEqual(repository.ledger, .empty)
    }

    func testPipelinePushesPendingEvidenceInStableOrderBeforeFetch() async throws {
        let userId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_788_100_000)
        var adultReceipt = makeAdultReceipt(
            ownerUserId: userId,
            recordedAt: recordedAt
        )
        adultReceipt.syncedUserId = nil
        adultReceipt.recordedAt = nil
        var termsReceipt = makeTermsReceipt(
            ownerUserId: userId,
            recordedAt: recordedAt.addingTimeInterval(1)
        )
        termsReceipt.syncedUserId = nil
        termsReceipt.recordedAt = nil
        var aiEvent = makeAIConsentEvent(
            ownerUserId: userId,
            recordedAt: recordedAt.addingTimeInterval(2),
            consentRevision: 1
        )
        aiEvent.syncedUserId = nil
        aiEvent.recordedAt = nil
        aiEvent.consentRevision = nil
        var analyticsEvent = makeAnalyticsEvent(
            ownerUserId: userId,
            eventKind: .granted,
            recordedAt: recordedAt.addingTimeInterval(3)
        )
        analyticsEvent.syncedUserId = nil
        analyticsEvent.recordedAt = nil

        let store = FaultInjectingConsentLedgerStore()
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: userId,
                termsReceipts: [termsReceipt],
                aiConsentEvents: [aiEvent],
                adultEligibilityReceipts: [adultReceipt],
                analyticsConsentEvents: [analyticsEvent]
            )
        )
        let repository = ConsentLedgerRepository(store: store)
        var operations: [String] = []
        var mergeResults: [ConsentSynchronizationMergePolicy.Result] = []
        let remoteService = ConsentRemoteService(dependencies: .init(
            insertAdultEligibilityReceipt: { _ in
                operations.append("adult-insert")
            },
            insertTermsReceipt: { _ in
                operations.append("terms-insert")
            },
            appendAIConsentEvent: { parameters in
                operations.append("ai-append")
                return [self.appendResult(id: parameters.p_id, revision: 1)]
            },
            appendAnalyticsConsentEvent: { parameters in
                operations.append("analytics-append")
                return [self.appendResult(id: parameters.p_id, revision: 2)]
            },
            fetchAdultEligibilityReceipt: { _, _ in
                operations.append("adult-readback")
                return [self.adultRow(adultReceipt, userId: userId)]
            },
            fetchTermsReceipt: { _, _ in
                operations.append("terms-readback")
                return [self.termsRow(termsReceipt, userId: userId)]
            },
            fetchAIConsentEvent: { _, _ in
                throw StubError.unexpected
            },
            fetchAnalyticsConsentEvent: { _, _ in
                throw StubError.unexpected
            },
            fetchRemoteRows: { receivedUserId in
                XCTAssertEqual(receivedUserId, userId)
                operations.append("authoritative-fetch")
                return .init(
                    adultEligibilityReceipts: [],
                    termsReceipts: [],
                    aiConsentEvents: [],
                    analyticsConsentEvents: [],
                    aiConsentStreamHeads: [],
                    analyticsConsentStreamHeads: []
                )
            }
        ))
        let coordinator = makeCoordinator(
            repository: repository,
            remoteService: remoteService,
            observedUserId: { userId },
            sdkUserId: { userId },
            didMergeRemoteState: { result, _ in
                mergeResults.append(result)
            }
        )

        try await coordinator.synchronize(for: userId)

        XCTAssertEqual(
            operations,
            [
                "adult-insert",
                "adult-readback",
                "terms-insert",
                "terms-readback",
                "ai-append",
                "analytics-append",
                "authoritative-fetch"
            ]
        )
        XCTAssertEqual(mergeResults.count, 1)
        XCTAssertEqual(
            repository.ledger.adultEligibilityReceipts.first?.syncedUserId,
            userId
        )
        XCTAssertEqual(
            repository.ledger.termsReceipts.first?.syncedUserId,
            userId
        )
        XCTAssertEqual(
            repository.ledger.aiConsentEvents.first?.syncedUserId,
            userId
        )
        XCTAssertEqual(
            repository.ledger.analyticsConsentEvents.first?.syncedUserId,
            userId
        )
    }

    private func makeCoordinator(
        userId: UUID,
        customSynchronizationOperation:
            @escaping ConsentSynchronizationCoordinator.SynchronizationOperation,
        failureHandler: @escaping @MainActor (Error, UUID, UInt) -> Void
    ) -> ConsentSynchronizationCoordinator {
        makeCoordinator(
            repository: ConsentLedgerRepository(
                store: FaultInjectingConsentLedgerStore()
            ),
            remoteService: unexpectedRemoteService(),
            customSynchronizationOperation: customSynchronizationOperation,
            observedUserId: { userId },
            sdkUserId: { userId },
            failureHandler: failureHandler
        )
    }

    private func makeCoordinator(
        repository: ConsentLedgerRepository,
        remoteService: ConsentRemoteService? = nil,
        customSynchronizationOperation:
            ConsentSynchronizationCoordinator.SynchronizationOperation? = nil,
        observedUserId: @escaping @MainActor () -> UUID?,
        sdkUserId: @escaping @MainActor () -> UUID?,
        didMergeRemoteState: @escaping @MainActor (
            ConsentSynchronizationMergePolicy.Result,
            UUID
        ) -> Void = { _, _ in },
        failureHandler: @escaping @MainActor (Error, UUID, UInt) -> Void = { _, _, _ in }
    ) -> ConsentSynchronizationCoordinator {
        let coordinator = ConsentSynchronizationCoordinator(
            ledgerRepository: repository,
            remoteService: remoteService ?? unexpectedRemoteService(),
            customSynchronizationOperation: customSynchronizationOperation
        )
        coordinator.setHandlers(
            observedUserIdProvider: observedUserId,
            sdkUserIdProvider: sdkUserId,
            didBindUnownedRecords: {},
            willMergeRemoteState: {},
            didMergeRemoteState: didMergeRemoteState,
            failureHandler: failureHandler
        )
        return coordinator
    }

    private func unexpectedRemoteService() -> ConsentRemoteService {
        ConsentRemoteService(dependencies: .init(
            insertAdultEligibilityReceipt: { _ in throw StubError.unexpected },
            insertTermsReceipt: { _ in throw StubError.unexpected },
            appendAIConsentEvent: { _ in throw StubError.unexpected },
            appendAnalyticsConsentEvent: { _ in throw StubError.unexpected },
            fetchAdultEligibilityReceipt: { _, _ in throw StubError.unexpected },
            fetchTermsReceipt: { _, _ in throw StubError.unexpected },
            fetchAIConsentEvent: { _, _ in throw StubError.unexpected },
            fetchAnalyticsConsentEvent: { _, _ in throw StubError.unexpected },
            fetchRemoteRows: { _ in throw StubError.unexpected }
        ))
    }

    private func emptyRemoteState() -> ConsentManager.RemoteState {
        .init(
            adultEligibilityReceipt: nil,
            termsReceipt: nil,
            aiConsentEvent: nil,
            analyticsConsentEvent: nil,
            aiConsentStreamHead: nil,
            analyticsConsentStreamHead: nil
        )
    }

    private func appendResult(
        id: UUID,
        revision: Int64
    ) -> ConsentRemoteWire.ConsentAppendResult {
        .init(
            accepted: true,
            event_revision: revision,
            accepted_parent_id: nil,
            authoritative_revision: revision,
            authoritative_event_id: id,
            recorded_at: "2026-09-05T12:00:00.000Z"
        )
    }

    private func adultRow(
        _ receipt: ConsentManager.AdultEligibilityReceipt,
        userId: UUID
    ) -> ConsentRemoteWire.AdultEligibilityReceipt {
        .init(
            id: receipt.id,
            user_id: userId,
            policy_version: receipt.policyVersion,
            confirmed_at: timestamp(receipt.confirmedAt),
            confirmation_method: receipt.confirmationMethod.rawValue,
            confirmation_text: receipt.confirmationText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild,
            recorded_at: "2026-09-05T12:00:00.000Z"
        )
    }

    private func termsRow(
        _ receipt: ConsentManager.TermsAcceptanceReceipt,
        userId: UUID
    ) -> ConsentRemoteWire.TermsReceipt {
        .init(
            id: receipt.id,
            user_id: userId,
            terms_version: receipt.termsVersion,
            accepted_at: timestamp(receipt.acceptedAt),
            acceptance_text: receipt.acceptanceText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild,
            recorded_at: "2026-09-05T12:00:00.000Z"
        )
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        )
    }

    private func assertThrowsStubError(
        _ task: Task<Void, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await task.value
            XCTFail("Synchronization must propagate the shared failure.", file: file, line: line)
        } catch {
            XCTAssertTrue(error is StubError, file: file, line: line)
        }
    }

    private func assertEventually(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 200 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied.", file: file, line: line)
    }

    private func drainTasks() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }
}

private enum StubError: Error {
    case unavailable
    case unexpected
}

@MainActor
private final class ConsentSynchronizationTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
