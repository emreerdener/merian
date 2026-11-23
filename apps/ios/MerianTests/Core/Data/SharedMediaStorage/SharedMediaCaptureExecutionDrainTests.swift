import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Accepted Capture execution lifetime", .serialized, .timeLimit(.minutes(1)))
struct SharedMediaCaptureExecutionDrainTests {
    typealias Candidate = SharedMediaCaptureExecutionRecovery.Candidate

    @Test func shutdownWaitsForIgnoringClaimAndPreventsDispatch() async {
        let gate = InferenceOperationGate(), owner = UUID()
        let pending = candidate()
        var released = 0
        let worker = SharedMediaCaptureExecutionDrain(dependencies: .init(begin: {
            .init(ownerID: owner, isCurrent: { true }, release: { released += 1 })
        }, page: { _, _ in .init(candidates: [pending], nextCursor: nil) }, claim: { _, _, _ in
            await gate.wait() // Models a persistence task that must actually exit.
            return candidate(scan: pending.scanID, generation: pending.generation, status: .running, count: 1)
        }, execute: { _, _ in Issue.record("Closed worker dispatched inference") },
        postpone: { _, _, _ in Issue.record("Closed worker changed retry metadata"); return false }))
        let work = Task { await worker.drain() }
        await gate.waitUntilStarted()
        let close = Task { await worker.close() }
        while !worker.isClosed { await Task.yield() }
        #expect(worker.isRunning && released == 0)
        await gate.release(); await close.value; await work.value
        #expect(!worker.isRunning && released == 1)
    }

    @Test func uncertainExecutionKeepsClaimedIdentityAndCoalescesWaiters() async {
        let gate = InferenceOperationGate(), owner = UUID(), pending = candidate()
        var begins = 0, claims = 0, executions = 0, released = 0
        var postponed: Candidate?
        let worker = SharedMediaCaptureExecutionDrain(dependencies: .init(begin: {
            begins += 1
            return .init(ownerID: owner, isCurrent: { true }, release: { released += 1 })
        }, page: { _, _ in .init(candidates: [pending], nextCursor: nil) }, claim: { value, _, _ in
            claims += 1
            #expect(value == pending)
            return candidate(scan: value.scanID, generation: value.generation, status: .running, count: 1)
        }, execute: { value, _ in
            executions += 1
            #expect(value.scanID == pending.scanID && value.generation == pending.generation)
            await gate.wait()
            throw URLError(.networkConnectionLost)
        }, postpone: { value, due, _ in
            postponed = value
            #expect(value.status == .running && value.attemptCount == 1 && due > Date())
            return true
        }, sleep: { _ in try await Task.sleep(for: .seconds(60)) }))
        let first = Task { await worker.drain() }
        await gate.waitUntilStarted()
        var secondStarted = false
        let second = Task { secondStarted = true; await worker.drain() }
        while !secondStarted { await Task.yield() }
        await gate.release(); await first.value; await second.value
        await worker.close()
        #expect(begins == 1 && claims == 1 && executions == 1 && released == 1)
        #expect(postponed?.scanID == pending.scanID && postponed?.generation == pending.generation)
    }

    @Test func ambiguousClaimSaveDoesNotDispatchOrInventPostponement() async {
        let pending = candidate(), owner = UUID()
        var released = 0, claims = 0
        let worker = SharedMediaCaptureExecutionDrain(dependencies: .init(begin: {
            .init(ownerID: owner, isCurrent: { true }, release: { released += 1 })
        }, page: { _, _ in .init(candidates: [pending], nextCursor: nil) }, claim: { _, _, _ in
            claims += 1
            throw SharedMediaStorageFailure.unavailable
        }, execute: { _, _ in Issue.record("Ambiguous claim dispatched") },
        postpone: { _, _, _ in Issue.record("Ambiguous claim invented an acknowledged attempt"); return false },
        sleep: { _ in try await Task.sleep(for: .seconds(60)) }))
        await worker.drain(); await worker.close()
        #expect(claims == 1 && released == 1)
    }

    @Test func exhaustedRetriesPauseWithoutDispatchOrAnotherWake() async {
        let pending = candidate(count: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts), owner = UUID()
        var paused = false
        let worker = SharedMediaCaptureExecutionDrain(dependencies: .init(begin: {
            .init(ownerID: owner, isCurrent: { true }, release: {})
        }, page: { _, _ in .init(candidates: [pending], nextCursor: nil) }, claim: { value, _, _ in
            Issue.record("Retry limit claimed another attempt"); return value
        }, execute: { _, _ in Issue.record("Retry limit dispatched") }, postpone: { value, _, _ in
            #expect(value == pending); paused = true; return false
        }, sleep: { _ in Issue.record("Paused execution scheduled another wake") }))
        await worker.drain(); await worker.close()
        #expect(paused)
    }

    @Test func savedDispatchCanOnlyEnterRecovery() async {
        var pending = candidate(count: 1)
        pending.dispatch = .init(version: 1, id: UUID(), scanID: pending.scanID, generation: pending.generation, attemptCount: 1)
        let saved = pending, owner = UUID()
        var recovered = false, postponed = false
        let worker = SharedMediaCaptureExecutionDrain(dependencies: .init(begin: {
            .init(ownerID: owner, isCurrent: { true }, release: {})
        }, page: { _, _ in .init(candidates: [saved], nextCursor: nil) }, claim: { value, _, _ in value },
        execute: { _, _ in Issue.record("Saved dispatch repeated primary inference") },
        postpone: { value, _, _ in #expect(value.dispatch == saved.dispatch); postponed = true; return true },
        recover: { value, _ in
            #expect(value.dispatch == saved.dispatch); recovered = true
            throw SharedMediaStorageFailure.unavailable
        }, sleep: { _ in try await Task.sleep(for: .seconds(60)) }))
        await worker.drain(); await worker.close()
        #expect(recovered && postponed)
    }

    @Test func unresolvedFundingWaitsWithoutConsumingExecutionAttempts() async {
        let pending = candidate(), owner = UUID()
        var checks = 0
        let worker = SharedMediaCaptureExecutionDrain(dependencies: .init(begin: {
            .init(ownerID: owner, isCurrent: { true }, release: {})
        }, page: { _, _ in .init(candidates: [pending], nextCursor: nil) }, claim: { value, _, _ in
            Issue.record("Unresolved funding consumed an execution attempt"); return value
        }, execute: { _, _ in Issue.record("Unresolved funding dispatched") },
        postpone: { _, _, _ in Issue.record("Funding wait changed execution retry metadata"); return false },
        prepareFunding: { value, _ in #expect(value == pending); checks += 1; return false },
        sleep: { _ in try await Task.sleep(for: .seconds(60)) }))
        await worker.drain(); await worker.close()
        #expect(checks == 1)
    }

    private func candidate(scan: UUID = UUID(), generation: UUID = UUID(),
                           status: OfflineJobStatus = .pending, count: Int = 0) -> Candidate {
        .init(scanID: scan, generation: generation, status: status, attemptCount: count, due: nil)
    }
}
