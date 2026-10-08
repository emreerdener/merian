import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioQueueExecutionTests {
    typealias Store = ObservationAudioExecutionStore
    let fixture = ObservationAudioExecutionServiceTests()

    @Test(arguments: ["normal", "offline", "generation", "container", "auth"])
    func queueCoalescesAndFencesKnownAnswer(change: String) async throws {
        let seed = try await fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let snapshot = try fixture.entry(seed, mode: "consumed"), proof = try seed.proof
        let key = ObservationAudioExecutionOwner.Key(snapshot: snapshot,
            session: .init(userID: seed.source.ownerID, isAnonymous: false), generation: 7, container: ObjectIdentifier(seed.container))
        let queue = OfflineQueueManager.shared, previous = queue.modelContext, online = queue.isOnline
        #expect(!queue.audioExecutionOwner.isRunning)
        queue.modelContext = ModelContext(seed.container); queue.isOnline = true
        defer { queue.modelContext = previous; queue.isOnline = online }
        let erasure = ObservationReanalysisErasureOwner(files: .init(documents: seed.root))
        let entered = AsyncStream<Void>.makeStream(), exited = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); exited.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, generation: UInt64 = 7, completed = 0, finished = false
        let cloud = ObservationAudioExecutionOwnerTests().account(key) { finished = true; exited.continuation.yield(()) }
        let bytes = try ObservationAudioCompletionTests().result(seed)
        let service = ObservationAudioExecutionService(dependencies: .init(read: { _, _, _ in Issue.record("Recovery read files"); throw MerianError.invalidResponse },
            upload: { _, _, _ in Issue.record("Recovery uploaded"); throw MerianError.invalidResponse },
            authorize: { _, _ in Issue.record("Recovery requested consent"); throw MerianError.invalidResponse },
            analyze: { _, _, _, _ in Issue.record("Recovery dispatched"); throw MerianError.invalidResponse },
            outcome: { _, before, after in
                try before()
                await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
                try after(); return bytes
            }))
        let current: @MainActor @Sendable (AuthTransitionSession, UInt64) -> Bool = { $0 == key.session && $1 == generation }
        func start() -> ObservationAudioExecutionOwner.Admission {
            queue.requestAudioExecution(key, proof: proof, account: cloud, service: service, erasure: erasure,
                isCurrentAccount: current, didComplete: { #expect(!finished); completed += 1 })
        }
        #expect(start() == .started)
        var begin = entered.stream.makeAsyncIterator(); _ = await begin.next()
        #expect(start() == .coalesced)
        switch change {
        case "offline": queue.isOnline = false; queue.audioExecutionOwner.cancel()
        case "generation": generation += 1
        case "container": queue.modelContext = nil
        case "auth": queue.audioExecutionOwner.invalidate()
        default: break
        }
        #expect(queue.audioExecutionOwner.isRunning && !finished)
        try #require(release).resume()
        var end = exited.stream.makeAsyncIterator(); _ = await end.next()
        await queue.audioExecutionOwner.invalidateAndAwait()
        let context = ModelContext(seed.container)
        let shouldComplete = change == "normal" || change == "offline"
        #expect(completed == (shouldComplete ? 1 : 0))
        #expect(try context.fetch(FetchDescriptor<LocalAnalysisRecord>()).count == (shouldComplete ? 2 : 1))
        let receipt = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.preparation.identity.analysisID))
        if shouldComplete { #expect(receipt?.status == (change == "normal" ? .complete : .pending)) } else { #expect(receipt == nil) }
        #expect(FileManager.default.fileExists(atPath: seed.root.appendingPathComponent(seed.preparation.path).path) == (change != "normal"))
    }

    @Test func completionCallbackRemainsInsideLeaseAndAuthDrain() async throws {
        let seed = try await fixture.fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let snapshot = try fixture.entry(seed, mode: "consumed"), proof = try seed.proof
        let key = ObservationAudioExecutionOwner.Key(snapshot: snapshot,
            session: .init(userID: seed.source.ownerID, isAnonymous: false), generation: 1, container: ObjectIdentifier(seed.container))
        let owner = ObservationAudioExecutionOwner(), boundary = try ObservationAudioExecutionServiceTests.Boundary(seed)
        let entered = AsyncStream<Void>.makeStream(); defer { entered.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, finished = false, drained = false
        let cloud = ObservationAudioExecutionOwnerTests().account(key) { finished = true }
        let admission = owner.start(key, account: cloud, isCurrent: { true }, operation: { scope in
            let result = await boundary.service.run(snapshot, proof: proof, container: seed.container, scope: scope, cleanup: { receipt in
                let persisted = try? ModelContext(seed.container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID))
                #expect(persisted != nil)
                await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
            })
            #expect(result == .completed)
        }, didFinish: {})
        #expect(admission == .started)
        var begin = entered.stream.makeAsyncIterator(); _ = await begin.next()
        let drain = Task { await owner.invalidateAndAwait(); drained = true }
        await Task.yield()
        #expect(owner.isRunning && !finished && !drained)
        try #require(release).resume(); await drain.value
        #expect(finished && drained && !owner.isRunning)
    }

    @Test func connectivityPredicateDoesNotInvalidateSettlement() async throws {
        let seed = try fixture.fixture.fixture.seed(action: .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let support = ObservationAudioExecutionOwnerTests(), key = try support.key(seed), owner = ObservationAudioExecutionOwner()
        var online = false
        #expect(owner.start(key, account: support.account(key), isCurrent: { true }, permitsDispatch: { online },
            operation: { _ in Issue.record("Offline admission") }, didFinish: {}) == .unavailable)
        online = true
        let exited = AsyncStream<Void>.makeStream(); defer { exited.continuation.finish() }
        let admission = owner.start(key, account: support.account(key), isCurrent: { true }, permitsDispatch: { online }, operation: { scope in
            #expect(scope.mayDispatch()); online = false
            #expect(!scope.mayDispatch() && scope.maySettleKnownReceipt())
        }, didFinish: { exited.continuation.yield(()) })
        #expect(admission == .started)
        var end = exited.stream.makeAsyncIterator(); _ = await end.next()
    }
}
