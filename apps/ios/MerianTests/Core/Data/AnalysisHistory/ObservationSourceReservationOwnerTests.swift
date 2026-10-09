import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationSourceReservationOwnerTests {
    typealias Owner = ObservationSourceReservationOwner

    func key(_ seed: ObservationReanalysisRecoveryTests.Seed) async throws -> Owner.Key {
        let fixture = ObservationSourceStoreTests()
        let admission = try await fixture.prepare(seed)
        let saved = try ObservationSourceReservationStore.stage(admission, request: fixture.request(seed),
            proof: .photo(seed.pending.verified(source: seed.source)), container: seed.container, isCurrent: { true })
        return .init(snapshot: saved, admission: .initial,
            session: .init(userID: saved.identity.ownerID, isAnonymous: false), generation: 1, container: ObjectIdentifier(seed.container))
    }
    func account(_ key: Owner.Key, finish: @escaping () -> Void = {}) -> ObservationHistoryCloudClient {
        .init(begin: { owner in
            #expect(owner == key.session.userID)
            return .init(id: UUID(), session: key.session)
        }, isCurrent: { $0.session == key.session }, finish: { _ in finish() }, fetch: { _ in
            Issue.record("Owner must not fetch history"); throw MerianError.invalidResponse
        })
    }

    @Test func exactCoalescingRetainsLeaseAndOnlyActualExitNotifies() async throws {
        let seed = try ObservationReanalysisRecoveryTests().seed(action: .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await key(seed), owner = Owner(), entered = AsyncStream<Void>.makeStream(), exited = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); exited.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, scope: Owner.Scope?, finishedLease = false, exits = 0
        let cloud = account(key) { finishedLease = true }
        let admission = owner.start(key, account: cloud, isCurrent: { true }, operation: {
            scope = $0
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
            #expect(scope?.maySettleKnownReceipt() == true && scope?.mayDispatch() == false)
        }, didFinish: {
            #expect(finishedLease && !owner.isRunning); exits += 1; exited.continuation.yield(())
        })
        #expect(admission == .started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in Issue.record("Duplicate") },
            didFinish: { Issue.record("Joiner notification") }) == .coalesced)
        owner.cancel()
        #expect(owner.isRunning && !finishedLease && scope?.maySettleKnownReceipt() == true && scope?.mayDispatch() == false)
        #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in }, didFinish: {}) == .unavailable)
        try #require(release).resume()
        var end = exited.stream.makeAsyncIterator(); _ = await end.next()
        #expect(exits == 1 && scope?.maySettleKnownReceipt() == false)
    }

    @Test(arguments: ["generation", "container", "session", "request", "claim"])
    func changedScopeCannotJoinOrReplaceActiveWork(change: String) async throws {
        let fixture = ObservationReanalysisRecoveryTests(), seed = try fixture.seed(action: .submit), other = try fixture.seed(action: .submit)
        defer { try? FileManager.default.removeItem(at: seed.root); try? FileManager.default.removeItem(at: other.root) }
        let key = try await key(seed), otherKey = try await self.key(other), owner = Owner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?
        #expect(owner.start(key, account: account(key), isCurrent: { true }, operation: { _ in
            await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: {}) == .started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        let changedWork = try ObservationSourceReservationWork(preparation: key.snapshot.work.preparation,
            request: key.snapshot.work.request, state: .running, generation: 1)
        let changedSnapshot = try ObservationSourceReservationStore.Snapshot(work: changedWork,
            metadata: #require(String(bytes: try changedWork.storedData(), encoding: .utf8)), containerID: key.container)
        let changed = Owner.Key(snapshot: change == "request" ? otherKey.snapshot : change == "claim" ? changedSnapshot : key.snapshot,
            admission: .initial, session: change == "session" ? .init(userID: key.session.userID, isAnonymous: true) : key.session,
            generation: change == "generation" ? 2 : 1, container: change == "container" ? otherKey.container : key.container)
        #expect(owner.start(changed, account: account(key), isCurrent: { true }, operation: { _ in Issue.record("Scope substituted") },
            didFinish: {}) == .unavailable)
        try #require(release).resume(); await owner.invalidateAndAwait()
    }

    @Test func overlappingAuthDrainsWaitForLeaseExitAndPreventReentry() async throws {
        let seed = try ObservationReanalysisRecoveryTests().seed(action: .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await key(seed), owner = Owner(), entered = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, scope: Owner.Scope?, finished = false, drained = false
        let cloud = account(key) { finished = true }
        let admission = owner.start(key, account: cloud, isCurrent: { true }, operation: {
            scope = $0; await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
        }, didFinish: {
            #expect(finished)
            #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in }, didFinish: {}) == .unavailable)
        })
        #expect(admission == .started)
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        owner.invalidate()
        #expect(scope?.mayDispatch() == false && scope?.maySettleKnownReceipt() == false)
        let first = Task { await owner.invalidateAndAwait(); drained = true }
        let second = Task { await owner.invalidateAndAwait() }
        await Task.yield()
        #expect(owner.isRunning && !finished && !drained)
        try #require(release).resume(); await first.value; await second.value
        #expect(finished && drained && !owner.isRunning)
        #expect(owner.start(key, account: cloud, isCurrent: { true }, operation: { _ in }, didFinish: {}) == .started)
        await owner.invalidateAndAwait()
    }

    @Test func invalidationGapAndStaleEnvironmentDenyAdmission() async throws {
        let seed = try ObservationReanalysisRecoveryTests().seed(action: .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await key(seed), owner = Owner()
        owner.invalidate()
        #expect(owner.start(key, account: account(key), isCurrent: { true }, operation: { _ in }, didFinish: {}) == .unavailable)
        await owner.invalidateAndAwait()
        #expect(owner.start(key, account: account(key), isCurrent: { false }, operation: { _ in }, didFinish: {}) == .unavailable)
    }

    @Test(arguments: ["environment", "lease", "session", "begin"])
    func accountLossNeverInvokesOperationAndStillReleasesAcquiredLease(change: String) async throws {
        let seed = try ObservationReanalysisRecoveryTests().seed(action: .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let key = try await key(seed), owner = Owner(), exited = AsyncStream<Void>.makeStream()
        defer { exited.continuation.finish() }
        var current = true, released = 0
        var cloud = account(key) { released += 1 }
        cloud.begin = { _ in
            if change == "begin" { throw MerianError.invalidResponse }
            if change == "environment" { current = false }
            return .init(id: UUID(), session: change == "session" ? .init(userID: UUID(), isAnonymous: false) : key.session)
        }
        cloud.isCurrent = { _ in change != "lease" }
        #expect(owner.start(key, account: cloud, isCurrent: { current }, operation: { _ in Issue.record("Stale operation") },
            didFinish: { exited.continuation.yield(()) }) == .started)
        var iterator = exited.stream.makeAsyncIterator(); _ = await iterator.next()
        #expect(released == (change == "begin" ? 0 : 1) && !owner.isRunning)
    }

    @Test func bothAuthBarriersAndConnectivityCloseSourceWorkWithoutAutomaticAdmission() throws {
        let root = "apps/ios/Merian/Core/Data/OfflineSync/"
        for path in ["Services/OfflineQueueManager+ReanalysisExecution.swift", "Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"] {
            let source = try DatabaseActorTestSupport.loadRepositorySource(at: root + path)
            let invalidate = try #require(source.range(of: "sourceReservationOwner.invalidate()"))
            let drain = try #require(source.range(of: "await sourceReservationOwner.invalidateAndAwait()"))
            #expect(invalidate.lowerBound < drain.lowerBound)
        }
        let manager = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineQueueManager.swift")
        #expect(manager.components(separatedBy: "self.sourceReservationOwner.cancel()").count == 3)
        let scheduler = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineJobScheduler.swift")
        #expect(!scheduler.contains("sourceReservationOwner"))
    }
}
