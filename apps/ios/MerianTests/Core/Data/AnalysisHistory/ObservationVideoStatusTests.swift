import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager), .timeLimit(.minutes(1)))
struct ObservationVideoStatusTests {
    @Test func pagingPreservesOmissionsAndRejectsOtherMediaCursors() async throws {
        let seed = try await ObservationVideoResumeStoreTests().seed("ready"); defer { seed.remove() }
        let context = ModelContext(seed.container)
        for index in 1...20 {
            let child = try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 100)))
            try #require(!Set([seed.source.observationID, seed.source.analysisID, seed.preparation.identity.analysisID]).contains(child))
            let identity = OfflineQueueWork.Reanalysis(observationID: seed.source.observationID,
                sourceAnalysisID: seed.source.analysisID, analysisID: child, ownerID: seed.source.ownerID)
            try ObservationReanalysisPersistence.insert(identity, paths: [], metadata: Data("{}".utf8), context: context)
        }
        try context.save()
        let reader = ObservationVideoSavedStatus()
        let first = try await reader.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            container: seed.container, isCurrent: { true })
        #expect(first.items.isEmpty && first.omittedCount == 20)
        let cursor = try #require(first.next)
        let last = try await reader.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            after: cursor, container: seed.container, isCurrent: { true })
        #expect(last.items == [.init(identity: seed.preparation.identity, phase: .prepared)] && last.next == nil)
        await #expect(throws: ObservationHistoryError.invalidPage) {
            try await ObservationAudioSavedStatus().page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
                after: cursor, container: seed.container, isCurrent: { true })
        }
        await #expect(throws: ObservationHistoryError.invalidPage) {
            try await reader.page(ownerID: seed.source.ownerID, observationID: UUID(),
                after: cursor, container: seed.container, isCurrent: { true })
        }
        let failing = ObservationVideoSavedStatus(read: { _, _, _ in throw CocoaError(.fileReadUnknown) })
        await #expect(throws: CocoaError(.fileReadUnknown)) {
            try await failing.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
                container: seed.container, isCurrent: { true })
        }
    }

    @Test func videoSharesCapacityAndAuthDrainWithAudio() async throws {
        let seed = try await ObservationVideoResumeStoreTests().seed("ready"); defer { seed.remove() }
        let queue = OfflineQueueManager.shared, owner = queue.audioStatusOwner, gate = Pause()
        await owner.invalidateAndAwait()
        defer { gate.release() }
        var finishes = 0, drained = false
        let account = ObservationReanalysisProducerTests().account(finish: { finishes += 1; #expect(owner.activeCount > 0) })
        let session = AuthTransitionSession(userID: seed.source.ownerID, isAnonymous: false)
        let reader = ObservationVideoSavedStatus(read: { identity, container, current in
            let saved = try await ObservationVideoResumeStore().read(identity, container: container, isCurrent: current)
            await gate.wait(); return saved
        })
        var tasks: [Task<ObservationVideoSavedStatus.Page, Error>] = []
        for limit in 1...4 {
            tasks.append(Task {
                try await owner.videoPage(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
                    session: session, generation: 1, limit: limit, container: seed.container, reader: reader,
                    account: account, isCurrent: { true })
            })
            await gate.entered()
        }
        await #expect(throws: ObservationAudioStatusOwner.Failure.capacity) {
            try await owner.page(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
                session: session, generation: 1, container: seed.container, reader: .init(), account: account, isCurrent: { true })
        }
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        let drain = Task {
            entered.continuation.yield(())
            await queue.awaitRetainedSyncQuiescenceForAuthTransition(); drained = true
        }
        for await _ in entered.stream { break }
        #expect(!drained && finishes == 0 && owner.activeCount == 4)
        gate.release(); await drain.value
        for task in tasks { await #expect(throws: (any Error).self) { try await task.value } }
        #expect(drained && finishes == 4 && owner.activeCount == 0)
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
