import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Completed Capture History continuation")
struct CaptureCompletedHistoryDrainTests {
    @Test func coordinatorKeepsFundingNudgeArrivingDuringHistorySweep() async throws {
        let dependencies = AppDIContainer.shared, gate = InferenceOperationGate()
        let coordinator = NativeMediaLifetimeCoordinator(manager: dependencies.supabaseManager,
            queue: dependencies.offlineQueueManager, repository: dependencies.scanRepository,
            mapStore: dependencies.privateScanMapStore)
        var passes = 0
        let drain = {
            passes += 1
            if passes == 1 { await gate.wait() }
        }
        try coordinator.requestCaptureHistoryForTesting(drain: drain)
        await gate.waitUntilStarted()
        try coordinator.requestCaptureHistoryForTesting(drain: drain)
        try coordinator.requestCaptureHistoryForTesting(drain: drain)
        #expect(passes == 1)
        await gate.release()
        while passes < 2 { await Task.yield() }
        // Both nudges coalesce, but the earlier page's omitted row is revisited.
        #expect(passes == 2)
    }

    private func candidate(releasing: Bool = false) -> SharedMediaCaptureCompletedRecovery.Candidate {
        .init(scanID: UUID(), generation: UUID(), releaseStarted: releasing)
    }

    @Test func coldDiscoveryFinishesWithoutAnotherUserAction() async {
        let id = UUID(), value = candidate()
        var finished = 0, released = 0
        let worker = CaptureCompletedHistoryDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { true }, release: { released += 1 })
        }, page: { cursor, _ in
            #expect(cursor == nil)
            return .init(candidates: [value], nextCursor: nil)
        }, finish: { found, scope in
            try scope.validate(); #expect(found == value); finished += 1
        }, sleep: { _ in Issue.record("Successful sweep should be idle") }))
        await worker.drain()
        #expect(finished == 1 && released == 1 && !worker.isRunning)
        await worker.close()
    }

    @Test func offlineSweepOnlyResumesAlreadyProvenCleanup() async {
        let id = UUID(), enrollment = candidate(), cleanup = candidate(releasing: true)
        var finished: [UUID] = [], released = 0
        let worker = CaptureCompletedHistoryDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { true }, release: { released += 1 })
        }, page: { _, _ in .init(candidates: [enrollment, cleanup], nextCursor: nil) }, finish: { value, _ in
            finished.append(value.scanID)
        }, canUseNetwork: { false }, sleep: { _ in
            #expect(released == 1)
            try await Task.sleep(for: .seconds(3600))
        }))
        await worker.drain()
        #expect(finished == [cleanup.scanID] && released == 1)
        await worker.close()
    }

    @Test func failedEnrollmentRetriesFromDurableDiscoveryWithFreshReleaseState() async {
        let id = UUID(), value = candidate(), timer = InferenceOperationGate()
        var attempts = 0, pages = 0, released = 0, sleeps = 0
        let worker = CaptureCompletedHistoryDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { true }, release: { released += 1 })
        }, page: { cursor, _ in
            #expect(cursor == nil); pages += 1
            return .init(candidates: [.init(scanID: value.scanID, generation: value.generation,
                releaseStarted: attempts > 0)], nextCursor: nil)
        }, finish: { found, _ in
            attempts += 1
            if attempts == 1 { throw SharedMediaStorageFailure.unavailable }
            #expect(found.releaseStarted)
        }, sleep: { delay in
            sleeps += 1
            #expect(delay == 5 && released == 1)
            await timer.wait()
        }))
        await worker.drain()
        #expect(attempts == 1 && released == 1)
        await timer.waitUntilStarted(); await timer.release()
        while released < 2 { await Task.yield() }
        await worker.close()
        #expect(attempts == 2 && pages == 2 && sleeps == 1)
    }

    @Test func closeJoinsCancellationIgnoringEnrollmentBeforeReleasingAccount() async {
        let id = UUID(), value = candidate(), gate = InferenceOperationGate()
        var released = false, closed = false
        let worker = CaptureCompletedHistoryDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { true }, release: { released = true })
        }, page: { _, _ in .init(candidates: [value], nextCursor: nil) }, finish: { _, _ in await gate.wait() }))
        let running = Task { await worker.drain() }
        await gate.waitUntilStarted()
        let closing = Task { await worker.close(); closed = true }
        while !worker.isClosed { await Task.yield() }
        #expect(!released && !closed && worker.isRunning)
        await gate.release()
        await closing.value; await running.value
        #expect(released && closed && !worker.isRunning)
    }

    @Test func accountChangeDuringDiscoveryCannotEnrollOrRelease() async {
        let id = UUID(), value = candidate(), gate = InferenceOperationGate()
        var current = true, released = 0
        let worker = CaptureCompletedHistoryDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { current }, release: { released += 1 })
        }, page: { _, _ in
            await gate.wait(); return .init(candidates: [value], nextCursor: nil)
        }, finish: { _, _ in Issue.record("Retired account performed an effect") }, isCurrent: { current },
        sleep: { _ in Issue.record("Retired account scheduled a retry") }))
        let running = Task { await worker.drain() }
        await gate.waitUntilStarted(); current = false; await gate.release()
        await running.value; await worker.close()
        #expect(released == 1)
    }

    @Test func boundedSweepPreservesCursorAndCoalescedWakeRevisitsEarlierRows() async {
        let id = UUID(), value = candidate(), pageGate = InferenceOperationGate(), timer = InferenceOperationGate()
        var pages = 0, sleeps = 0, finished = 0, released = 0
        let worker = CaptureCompletedHistoryDrain(dependencies: .init(begin: {
            .init(ownerID: id, isCurrent: { true }, release: { released += 1 })
        }, page: { cursor, _ in
            pages += 1
            if pages == 1 { await pageGate.wait() }
            if pages <= 9 {
                #expect(cursor == (pages == 1 ? nil : String(pages - 1)))
                return .init(candidates: [], nextCursor: pages == 9 ? nil : String(pages))
            }
            #expect(cursor == nil)
            return .init(candidates: [value], nextCursor: nil)
        }, finish: { _, _ in finished += 1 }, sleep: { delay in
            #expect(delay == 1); sleeps += 1
            if sleeps == 1 { await timer.wait() }
        }))
        let first = Task { await worker.drain() }
        await pageGate.waitUntilStarted()
        var entered = false
        let second = Task { entered = true; await worker.drain() }
        while !entered { await Task.yield() }
        await pageGate.release(); await first.value; await second.value
        #expect(pages == 8 && released == 1)
        await timer.waitUntilStarted(); await timer.release()
        while released < 3 { await Task.yield() }
        await worker.close()
        #expect(pages == 10 && sleeps == 2 && finished == 1)
    }
}
