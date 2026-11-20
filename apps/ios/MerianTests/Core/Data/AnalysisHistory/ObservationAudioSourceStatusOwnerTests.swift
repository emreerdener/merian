import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationAudioSourceStatusOwnerTests {
    let fixture = ObservationAudioSourceSubmissionTests()
    typealias Seed = ObservationAudioPreparationTests.Seed

    func request(_ owner: ObservationAudioStatusOwner, _ seed: Seed, reader: ObservationAudioSourceSavedStatus,
                 account: ObservationHistoryCloudClient, limit: Int = 20,
                 current: @escaping @MainActor @Sendable () -> Bool = { true }) async throws -> ObservationAudioSourceSavedStatus.Page {
        try await owner.sourcePage(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            session: .init(userID: seed.source.ownerID, isAnonymous: false), generation: 1, limit: limit,
            container: seed.container, reader: reader, account: account, isCurrent: current)
    }

    @Test func routesDoNotCoalesceAndShareCapacityAndDrain() async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.state("staged", seed: seed)
        let owner = ObservationAudioStatusOwner(), gate = Pause()
        defer { gate.release() }
        var finished = 0, sourceReads = 0, legacyReads = 0
        let account = ObservationReanalysisProducerTests().account(finish: { finished += 1; #expect(owner.activeCount > 0) })
        let reader = ObservationAudioSourceSavedStatus(read: { identity, container, current in
            sourceReads += 1
            let saved = try await ObservationAudioSourceResumeStore().read(identity, container: container, isCurrent: current)
            await gate.wait(); return saved
        })
        let legacyReader = ObservationAudioSavedStatus(read: { _, _, _ in
            legacyReads += 1; await gate.wait(); throw ObservationHistoryError.unavailable
        })
        let first = Task { try await request(owner, seed, reader: reader, account: account) }
        await gate.entered()
        let legacy = Task {
            try await owner.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
                session: .init(userID: seed.source.ownerID, isAnonymous: false), generation: 1,
                container: seed.container, reader: legacyReader, account: account, isCurrent: { true })
        }
        await gate.entered()
        var extra: [Task<ObservationAudioSourceSavedStatus.Page, Error>] = []
        for limit in 1...2 {
            extra.append(Task { try await request(owner, seed, reader: reader, account: account, limit: limit) }); await gate.entered()
        }
        #expect(owner.activeCount == 4 && sourceReads == 3 && legacyReads == 1 && finished == 0)
        await #expect(throws: ObservationAudioStatusOwner.Failure.capacity) { try await request(owner, seed, reader: reader, account: account, limit: 3) }
        owner.invalidate()
        let draining = Task { await owner.invalidateAndAwait() }
        await #expect(throws: ObservationAudioStatusOwner.Failure.draining) { try await request(owner, seed, reader: reader, account: account) }
        #expect(finished == 0 && owner.activeCount == 4)
        gate.release(); await draining.value
        await #expect(throws: (any Error).self) { try await first.value }
        await #expect(throws: (any Error).self) { try await legacy.value }
        for task in extra { await #expect(throws: (any Error).self) { try await task.value } }
        #expect(finished == 4 && owner.activeCount == 0)
    }

    @Test func cancelledSourceWaiterDoesNotCancelJoinedRead() async throws {
        let seed = try await fixture.fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.state("staged", seed: seed)
        let owner = ObservationAudioStatusOwner(), gate = Pause()
        defer { gate.release() }
        var calls = 0, finishes = 0
        let reader = ObservationAudioSourceSavedStatus(read: { identity, container, current in
            calls += 1
            let saved = try await ObservationAudioSourceResumeStore().read(identity, container: container, isCurrent: current)
            await gate.wait(); return saved
        })
        let account = ObservationReanalysisProducerTests().account(finish: { finishes += 1 })
        let first = Task { try await request(owner, seed, reader: reader, account: account) }
        await gate.entered()
        let joined = AsyncStream<Void>.makeStream(); defer { joined.continuation.finish() }
        let second = Task { try await request(owner, seed, reader: reader, account: account,
            current: { joined.continuation.yield(()); return true }) }
        for await _ in joined.stream { break }
        first.cancel()
        #expect(calls == 1 && finishes == 0 && owner.activeCount == 1)
        gate.release()
        await #expect(throws: CancellationError.self) { try await first.value }
        let page = try await second.value
        #expect(page.items.count == 1 && calls == 1 && finishes == 1 && owner.activeCount == 0)
    }

    private final class Pause {
        private let stream = AsyncStream<Void>.makeStream()
        private var pending: [CheckedContinuation<Void, Never>] = []
        deinit { stream.continuation.finish() }
        func wait() async { await withCheckedContinuation { pending.append($0); stream.continuation.yield(()) } }
        func entered() async { for await _ in stream.stream { break } }
        func release() { let saved = pending; pending.removeAll(); saved.forEach { $0.resume() } }
    }
}
