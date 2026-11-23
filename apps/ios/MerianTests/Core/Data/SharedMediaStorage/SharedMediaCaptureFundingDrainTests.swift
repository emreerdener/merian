import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Capture funding recovery lifecycle")
struct SharedMediaCaptureFundingDrainTests {
    private func candidate(due: Date? = nil) -> SharedMediaCaptureFundingRecovery.Candidate {
        .init(scanID: UUID(), generation: UUID(), due: due)
    }

    @Test func concurrentDrainsCoalesceAndReleaseTheAccountBeforeRetrySleep() async {
        let gate = InferenceOperationGate(), accountID = UUID(), value = candidate()
        var begins = 0, releases = 0, recovered = 0
        let owner = SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
            begins += 1
            return .init(ownerID: accountID, isCurrent: { true }, release: { releases += 1 })
        }, page: { _, _ in
            await gate.wait()
            return .init(candidates: [value], nextCursor: nil)
        }, recover: { _, _ in recovered += 1 }, postpone: { _, _, _ in Issue.record("Unexpected retry") },
        sleep: { _ in try await Task.sleep(for: .seconds(3600)) }))
        let first = Task { await owner.drain() }
        await gate.waitUntilStarted()
        var secondEntered = false
        let second = Task { secondEntered = true; await owner.drain() }
        while !secondEntered { await Task.yield() }
        await gate.release()
        await first.value; await second.value
        #expect(begins == 1 && releases == 1 && recovered == 1)
        await owner.close()
        #expect(owner.isClosed && !owner.isRunning)
    }

    @Test func futureReceiptWaitsAndFailedRetrySaveDoesNotDispatchAgain() async {
        let now = Date(timeIntervalSinceReferenceDate: 900_000_000), id = UUID()
        let due = candidate(), future = candidate(due: now.addingTimeInterval(20))
        var recovered: [UUID] = [], retries: [Date] = [], releases = 0
        let owner = SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { true }, release: { releases += 1 })
        }, page: { _, _ in .init(candidates: [due, future], nextCursor: nil) }, recover: { value, _ in
            recovered.append(value.scanID); throw SharedMediaStorageFailure.unavailable
        }, postpone: { value, date, _ in
            #expect(value == due); retries.append(date)
            throw SharedMediaStorageFailure.unavailable
        }, now: { now }, sleep: { _ in try await Task.sleep(for: .seconds(3600)) }))
        await owner.drain()
        #expect(recovered == [due.scanID] && retries == [now.addingTimeInterval(5)] && releases == 1)
        await owner.close()
        await owner.drain()
        #expect(recovered.count == 1)
    }

    @Test func accountTransitionJoinsCancellationIgnoringReadWithoutEffects() async {
        let gate = InferenceOperationGate(), id = UUID(), value = candidate()
        var current = true, released = false
        let owner = SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { current }, release: { released = true })
        }, page: { _, _ in
            await gate.wait()
            return .init(candidates: [value], nextCursor: nil)
        }, recover: { _, _ in Issue.record("Retired account delivered funding") },
        postpone: { _, _, _ in Issue.record("Retired account wrote retry") }))
        let running = Task { await owner.drain() }
        await gate.waitUntilStarted()
        current = false
        let closing = Task { await owner.close() }
        await Task.yield()
        #expect(!released)
        await gate.release()
        await closing.value; await running.value
        #expect(released && owner.isClosed && !owner.isRunning)
    }

    @Test func eachWakeBoundsDatabasePagesAndCarriesItsCursor() async {
        let id = UUID()
        let timer = InferenceOperationGate()
        var pages = 0, released = 0
        let owner = SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { true }, release: { released += 1 })
        }, page: { cursor, _ in
            #expect(cursor == (pages == 0 ? nil : String(pages)))
            pages += 1
            return .init(candidates: [], nextCursor: pages == 9 ? nil : String(pages))
        }, recover: { _, _ in Issue.record("Unexpected delivery") }, postpone: { _, _, _ in Issue.record("Unexpected retry") },
        sleep: { _ in await timer.wait() }))
        await owner.drain()
        #expect(pages == 8 && released == 1)
        await timer.waitUntilStarted()
        await timer.release()
        while pages < 9 { await Task.yield() }
        await owner.close()
        #expect(pages == 9 && released == 2)
    }

    @Test func transientAccountAdmissionRetriesWhileHostIsCurrent() async {
        let timer = InferenceOperationGate(), id = UUID()
        var begins = 0, pages = 0, released = 0
        let owner = SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
            begins += 1
            if begins == 1 { throw SharedMediaStorageFailure.unavailable }
            return .init(ownerID: id, isCurrent: { true }, release: { released += 1 })
        }, page: { _, _ in
            pages += 1
            return .init(candidates: [], nextCursor: nil)
        }, recover: { _, _ in Issue.record("Unexpected delivery") }, postpone: { _, _, _ in Issue.record("Unexpected retry") },
        sleep: { delay in
            #expect(delay > 0 && delay <= 5)
            await timer.wait()
        }))
        await owner.drain()
        #expect(begins == 1 && pages == 0 && released == 0)
        await timer.waitUntilStarted()
        await timer.release()
        while pages == 0 { await Task.yield() }
        await owner.close()
        #expect(begins == 2 && pages == 1 && released == 1)
    }

    @Test func retiredHostDoesNotRetryFailedAccountAdmission() async {
        let owner = SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
            throw SharedMediaStorageFailure.closed
        }, page: { _, _ in
            Issue.record("Retired host read storage")
            return .init(candidates: [], nextCursor: nil)
        }, recover: { _, _ in Issue.record("Unexpected delivery") }, postpone: { _, _, _ in Issue.record("Unexpected retry") },
        isCurrent: { false }, sleep: { _ in Issue.record("Retired host scheduled another admission") }))
        await owner.drain()
        await owner.close()
    }
}
