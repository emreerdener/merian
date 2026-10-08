import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationAudioStatusOwnerTests {
    typealias Owner = ObservationAudioStatusOwner
    typealias Seed = ObservationAudioPreparationTests.Seed
    let fixture = ObservationAudioPreparationTests()

    func request(_ owner: Owner, _ seed: Seed, reader: ObservationAudioSavedStatus? = nil,
                 account: ObservationHistoryCloudClient, generation: UInt64 = 1, limit: Int = 20,
                 current: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> ObservationAudioSavedStatus.Page {
        try await owner.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            session: .init(userID: seed.source.ownerID, isAnonymous: false), generation: generation, limit: limit,
            container: seed.container, reader: reader ?? .init(), account: account, isCurrent: current)
    }

    @Test func cancellingJoinedWaiterDoesNotCancelReadOrReleaseLeaseEarly() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        let owner = Owner(), gate = Pause(), joined = AsyncStream<Void>.makeStream()
        defer { gate.release(); joined.continuation.finish() }
        var calls = 0, finishes = 0
        let reader = ObservationAudioSavedStatus(read: { identity, container, current in
            calls += 1
            let saved = try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: current)
            await gate.wait(); return saved
        })
        let account = fixture.fixture.account(finish: { finishes += 1; #expect(owner.activeCount == 1) })
        let first = Task { try await request(owner, seed, reader: reader, account: account) }
        await gate.entered()
        let second = Task { try await request(owner, seed, reader: reader, account: account,
            current: { joined.continuation.yield(); return true }) }
        for await _ in joined.stream { break }
        first.cancel()
        #expect(calls == 1 && finishes == 0 && owner.activeCount == 1)
        gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        let result = try await second.value
        #expect(result.items.count == 1 && calls == 1 && finishes == 1 && owner.activeCount == 0)
    }

    @Test func fourDistinctPagesRetainSlotsThroughCancellationAndOverlappingDrains() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        let owner = Owner(), gate = Pause(), entered = AsyncStream<Void>.makeStream()
        defer { gate.release(); entered.continuation.finish() }
        var finished = 0, drained = 0
        let account = fixture.fixture.account(finish: { finished += 1; #expect(owner.activeCount > 0) })
        let reader = ObservationAudioSavedStatus(read: { identity, container, current in
            let result = try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: current)
            await gate.wait(); return result
        })
        var tasks: [Task<ObservationAudioSavedStatus.Page, Error>] = []
        for limit in 1...4 {
            tasks.append(Task { try await request(owner, seed, reader: reader, account: account, limit: limit) })
            await gate.entered()
        }
        await #expect(throws: Owner.Failure.capacity) { try await request(owner, seed, account: account, limit: 5) }
        owner.cancel(ownerID: seed.source.ownerID, observationID: UUID(), session: .init(userID: seed.source.ownerID, isAnonymous: false),
            generation: 1, in: seed.container)
        #expect(owner.activeCount == 4)
        let first = Task { entered.continuation.yield(); await owner.invalidateAndAwait(); drained += 1 }
        for await _ in entered.stream { break }
        let second = Task { entered.continuation.yield(); await owner.invalidateAndAwait(); drained += 1 }
        for await _ in entered.stream { break }
        #expect(owner.activeCount == 4 && finished == 0 && drained == 0)
        await #expect(throws: Owner.Failure.draining) { try await request(owner, seed, account: account) }
        gate.release(); await first.value; await second.value
        for task in tasks { await #expect(throws: (any Error).self) { try await task.value } }
        #expect(owner.activeCount == 0 && finished == 4 && drained == 2)
        let fresh = try await request(owner, seed, account: account, generation: 2)
        #expect(fresh.items.count == 1 && finished == 5)
    }

    @Test(arguments: ["begin", "session", "lease", "environment"])
    func invalidAccountNeverReadsAndReleasesEveryAcquiredLease(_ mode: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        let owner = Owner()
        var finished = 0, current = true, account = fixture.fixture.account(finish: { finished += 1 })
        account.begin = { id in
            if mode == "begin" { throw MerianError.invalidResponse }
            if mode == "environment" { current = false }
            return .init(id: UUID(), session: .init(userID: id, isAnonymous: mode == "session"))
        }
        account.isCurrent = { _ in mode != "lease" }
        let reader = ObservationAudioSavedStatus(read: { _, _, _ in Issue.record("Invalid account read private state"); throw MerianError.invalidResponse })
        await #expect(throws: (any Error).self) { try await request(owner, seed, reader: reader, account: account, current: { current }) }
        #expect(finished == (mode == "begin" ? 0 : 1) && owner.activeCount == 0)
    }

    @Test(arguments: ["retained", "background"])
    func bothQueueAuthDrainsWaitForActualReadExit(_ seam: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        let queue = OfflineQueueManager.shared, owner = queue.audioStatusOwner, gate = Pause(), entered = AsyncStream<Void>.makeStream()
        defer { gate.release(); entered.continuation.finish() }
        await owner.invalidateAndAwait()
        var finished = 0, drained = false
        let account = fixture.fixture.account(finish: { finished += 1; #expect(owner.activeCount == 1) })
        let reader = ObservationAudioSavedStatus(read: { identity, container, current in
            let result = try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: current)
            await gate.wait(); return result
        })
        let task = Task { try await request(owner, seed, reader: reader, account: account) }
        await gate.entered()
        let drain = Task {
            entered.continuation.yield()
            if seam == "retained" { await queue.awaitRetainedSyncQuiescenceForAuthTransition() } else { _ = await queue.quiesceBackgroundAccountWorkForAuthTransition(sourceUserID: seed.source.ownerID) }
            drained = true
        }
        for await _ in entered.stream { break }
        #expect(!drained && finished == 0 && owner.activeCount == 1)
        await #expect(throws: Owner.Failure.draining) { try await request(owner, seed, account: account) }
        gate.release(); await drain.value
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(drained && finished == 1 && owner.activeCount == 0)
    }

    @Test func laterInvalidationCannotBeClearedByAnEarlierDrain() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.phase(seed)
        let owner = Owner(), gate = Pause(), entered = AsyncStream<Void>.makeStream()
        defer { gate.release(); entered.continuation.finish() }
        let account = fixture.fixture.account()
        let reader = ObservationAudioSavedStatus(read: { identity, container, current in
            let result = try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: current)
            await gate.wait(); return result
        })
        let task = Task { try await request(owner, seed, reader: reader, account: account) }
        await gate.entered()
        let drain = Task { entered.continuation.yield(); await owner.invalidateAndAwait() }
        for await _ in entered.stream { break }
        owner.invalidate()
        gate.release(); await drain.value
        await #expect(throws: (any Error).self) { try await task.value }
        await #expect(throws: Owner.Failure.draining) { try await request(owner, seed, account: account) }
        await owner.invalidateAndAwait()
        let fresh = try await request(owner, seed, account: account)
        #expect(fresh.items.count == 1)
    }

    @Test func sourceBarriersInvalidateBeforeAwaitAndNeverScheduleLocalReads() throws {
        let root = "apps/ios/Merian/Core/Data/OfflineSync/"
        for path in ["Services/OfflineQueueManager+ReanalysisExecution.swift", "Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"] {
            let source = try DatabaseActorTestSupport.loadRepositorySource(at: root + path)
            let stop = try #require(source.range(of: "audioStatusOwner.invalidate()"))
            let wait = try #require(source.range(of: "await audioStatusOwner.invalidateAndAwait()"))
            #expect(stop.lowerBound < wait.lowerBound)
        }
        let scheduler = try DatabaseActorTestSupport.loadRepositorySource(at: root + "OfflineJobScheduler.swift")
        #expect(!scheduler.contains("audioStatusOwner"))
    }

    private final class Pause {
        private let stream = AsyncStream<Void>.makeStream()
        private var pending: [CheckedContinuation<Void, Never>] = []
        deinit { stream.continuation.finish() }
        func wait() async { await withCheckedContinuation { pending.append($0); stream.continuation.yield() } }
        func entered() async { for await _ in stream.stream { break } }
        func release() { let saved = pending; pending.removeAll(); saved.forEach { $0.resume() } }
    }
}
