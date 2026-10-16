import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoExecutionServiceTests {
    typealias Store = ObservationVideoExecutionStore
    typealias Seed = ObservationVideoDurabilityTests.Seed
    typealias Service = ObservationVideoExecutionService
    let fixture = ObservationVideoExecutionStoreTests()

    func seed(_ mode: String) async throws -> (Seed, Store.Snapshot) {
        let (seed, uploaded) = try await fixture.ready()
        let saved = try fixture.stage(seed, uploaded)
        if mode == "idle" { return (seed, saved) }
        let claim = try Store.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        let active = mode.contains("consumed") ? try Store.consume(claim, proof: seed.proof,
            authorization: fixture.authorization, container: seed.container, isCurrent: { true }).snapshot : claim.snapshot
        return (seed, mode.contains("held") ? try Store.hold(active, proof: seed.proof, container: seed.container, isCurrent: { true }) : active)
    }
    func owned(_ saved: Store.Snapshot, _ seed: Seed,
        _ body: @escaping @MainActor (ObservationVideoExecutionOwner.Scope, ObservationVideoExecutionOwner) async throws -> Void) async throws {
        let owner = ObservationVideoExecutionOwner(), support = ObservationVideoExecutionOwnerTests()
        let key = ObservationVideoExecutionOwner.Key(snapshot: saved, session: .init(userID: seed.source.ownerID, isAnonymous: false),
            generation: 1, container: ObjectIdentifier(seed.container))
        let exit = AsyncStream<Void>.makeStream(); defer { exit.continuation.finish() }
        var result: Result<Void, Error>?
        #expect(owner.start(key, account: support.account(key), isCurrent: { true }, operation: { scope in
            do { try await body(scope, owner); result = .success(()) } catch { result = .failure(error) }
        }, didFinish: { exit.continuation.yield(()) }) == .started)
        var iterator = exit.stream.makeAsyncIterator(); _ = await iterator.next()
        try #require(result).get()
    }
    @MainActor final class Boundary {
        let seed: Seed
        var events: [String] = []
        var hook: (String) throws -> Void = { _ in }
        var reply: ObservationAnalysisReceipt.State = .complete
        var bytes: Data?
        init(_ seed: Seed) throws { self.seed = seed; bytes = try ObservationVideoCompletionTests().result(seed.preparation.request) }
        func hit(_ phase: String) throws { events.append(phase); try hook(phase) }
        var service: Service {
            Service(dependencies: .init(authorize: { [self] owner, validate in
                try validate(); try hit("authorize"); #expect(owner == seed.source.ownerID)
                return .init(recipient: .gemini, validate: {})
            }, analyze: { [self] permit, _, before, after in
                try before(); #expect(permit.snapshot.work.consumed)
                try hit("analyze"); try after()
                return .init(observationID: permit.snapshot.work.request.observationID,
                    analysisID: permit.snapshot.work.request.analysisID, state: reply)
            }, outcome: { [self] saved, before, after in
                try before(); #expect(saved.work.consumed); try hit("outcome"); try after(); return bytes
            }))
        }
        func cleanup(_ receipt: ObservationReanalysisErasureReceipt) async {
            #expect(receipt.childID == seed.preparation.identity.analysisID)
            #expect((try? ModelContext(seed.container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID))) != nil)
            events.append("cleanup")
        }
    }

    @Test(arguments: ["idle", "running-consumed", "held-consumed", "running", "held"])
    func dispatchAndRecoveryHaveDisjointAuthority(mode: String) async throws {
        let (seed, saved) = try await seed(mode); defer { seed.remove() }
        let proof = try seed.proof
        let boundary = try Boundary(seed)
        try await owned(saved, seed) { scope, _ in
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup)
            #expect(outcome == (mode == "running" || mode == "held" ? .held : .completed))
        }
        #expect(boundary.events == (mode == "idle" ? ["authorize", "analyze", "outcome", "cleanup"]
            : mode.contains("consumed") ? ["outcome", "cleanup"] : []))
    }
    @Test(arguments: [false, true])
    func ambiguousConsumptionNeverInvokes(committed: Bool) async throws {
        let (seed, saved) = try await seed("idle"); defer { seed.remove() }
        let proof = try seed.proof
        let boundary = try Boundary(seed); var service = boundary.service
        service.consumeSave = { if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown) }
        let executor = service
        try await owned(saved, seed) { scope, _ in
            #expect(await executor.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup) == .held)
        }
        let held = try Store.read(proof: proof, container: seed.container, isCurrent: { true })
        #expect(held.work.phase == .held && held.work.consumed == committed && boundary.events == ["authorize"])
    }
    @Test(arguments: ["before", "authorize", "analyze", "outcome"], [false, true])
    func cancellationAndAccountLossRemainSeparate(phase: String, auth: Bool) async throws {
        let (seed, saved) = try await seed("idle"); defer { seed.remove() }
        let proof = try seed.proof
        let boundary = try Boundary(seed)
        try await owned(saved, seed) { scope, owner in
            if phase == "before" { if auth { owner.invalidate() } else { owner.cancel() } }
            boundary.hook = { if $0 == phase { if auth { owner.invalidate() } else { owner.cancel() } } }
            let result = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup)
            #expect(result == (auth || phase == "before" ? .unavailable : phase == "outcome" ? .completed : .held))
        }
        #expect(boundary.events.contains("cleanup") == (!auth && phase == "outcome"))
        if phase == "before" { #expect(boundary.events.isEmpty) }
        if phase == "authorize" { #expect(boundary.events == ["authorize"]) }
        if phase == "analyze" { #expect(!boundary.events.contains("outcome")) }
    }
    @Test(arguments: [ObservationAnalysisReceipt.State.admitted, .dispatched, .draft, .failedTerminal, .complete])
    func stateReceiptCannotReplaceExactResult(state: ObservationAnalysisReceipt.State) async throws {
        let (seed, saved) = try await seed("idle"); defer { seed.remove() }
        let proof = try seed.proof
        let boundary = try Boundary(seed); boundary.reply = state; boundary.bytes = nil
        try await owned(saved, seed) { scope, _ in
            #expect(await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup) == .held)
        }
        #expect(boundary.events.filter { $0 == "analyze" }.count == 1)
        #expect(boundary.events.contains("outcome") == (state == .complete))
        #expect(!boundary.events.contains("cleanup"))
    }
    @Test(arguments: ["missing", "malformed", "foreign", "throw"])
    func unknownConsumedOutcomesNeverReinvoke(reason: String) async throws {
        let (seed, saved) = try await seed("running-consumed"); defer { seed.remove() }
        let proof = try seed.proof
        let boundary = try Boundary(seed)
        if reason == "missing" { boundary.bytes = nil }
        if reason == "malformed" { boundary.bytes = Data("{}".utf8) }
        if reason == "foreign" {
            let bytes = try #require(boundary.bytes)
            var row = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            row["analysis_id"] = UUID().uuidString.lowercased(); boundary.bytes = try JSONSerialization.data(withJSONObject: row)
        }
        if reason == "throw" { boundary.hook = { _ in throw URLError(.timedOut) } }
        try await owned(saved, seed) { scope, _ in
            #expect(await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup) == .held)
        }
        #expect(boundary.events == ["outcome"])
    }
    @Test func preSyncedCompletionAndStaleSnapshotAreFenced() async throws {
        let (seed, saved) = try await seed("held-consumed"); defer { seed.remove() }
        let proof = try seed.proof
        let boundary = try Boundary(seed), context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let bytes = try #require(boundary.bytes)
        let result = try ObservationReanalysisResult.decode(bytes, matching: saved.work.request)
        _ = try ObservationHistorySyncService.insert([result], into: parent, ownerID: seed.source.ownerID, context: context); try context.save()
        try await owned(saved, seed) { scope, _ in
            #expect(await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup) == .completed)
        }
        #expect(boundary.events == ["outcome", "cleanup"])
    }
}
