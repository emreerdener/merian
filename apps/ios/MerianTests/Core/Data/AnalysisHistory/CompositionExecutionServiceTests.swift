import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CompositionExecutionServiceTests {
    typealias Store = ObservationCompositionExecutionStore
    typealias Seed = ObservationCompositionPreparationTests.Seed
    typealias Service = ObservationCompositionExecutionService
    let fixture = ObservationCompositionExecutionTests()

    func seed(_ mode: String) async throws -> (Seed, Store.Snapshot) {
        let (seed, uploaded) = try await fixture.uploaded()
        let saved = try Store.stage(uploaded, proof: seed.proof, authorization: fixture.authorization, container: seed.container, isCurrent: { true })
        if mode == "idle" { return (seed, saved) }
        let claim = try Store.claim(saved, proof: seed.proof, container: seed.container, isCurrent: { true })
        let active = mode.contains("consumed") ? try Store.consume(claim, proof: seed.proof,
            authorization: fixture.authorization, container: seed.container, isCurrent: { true }).snapshot : claim.snapshot
        return (seed, mode.contains("held") ? try Store.hold(active, proof: seed.proof, container: seed.container, isCurrent: { true }) : active)
    }
    func owned(_ saved: Store.Snapshot, _ seed: Seed,
               _ body: @escaping @MainActor (ObservationCompositionExecutionOwner.Scope, ObservationCompositionExecutionOwner) async throws -> Void) async throws {
        try await owned(saved, source: seed.source, container: seed.container, body)
    }
    func owned(_ saved: Store.Snapshot, source: ObservationReanalysisSource, container: ModelContainer,
               _ body: @escaping @MainActor (ObservationCompositionExecutionOwner.Scope, ObservationCompositionExecutionOwner) async throws -> Void) async throws {
        let owner = ObservationCompositionExecutionOwner()
        let key = ObservationCompositionExecutionOwner.Key(snapshot: saved, session: .init(userID: source.ownerID, isAnonymous: false),
            generation: 1, container: ObjectIdentifier(container))
        let exit = AsyncStream<Void>.makeStream(); defer { exit.continuation.finish() }
        var result: Result<Void, Error>?
        #expect(owner.start(key, account: account(key), isCurrent: { true }, operation: { scope in
            do { try await body(scope, owner); result = .success(()) } catch { result = .failure(error) }
        }, didFinish: { exit.continuation.yield(()) }) == .started)
        var iterator = exit.stream.makeAsyncIterator(); _ = await iterator.next()
        try #require(result).get()
    }
    func account(_ key: ObservationCompositionExecutionOwner.Key) -> ObservationHistoryCloudClient {
        .init(begin: { owner in
            #expect(owner == key.session.userID)
            return .init(id: UUID(), session: key.session)
        }, isCurrent: { $0.session == key.session }, finish: { _ in }, fetch: { _ in
            Issue.record("Owner must not fetch history"); throw MerianError.invalidResponse
        })
    }
    func result(_ request: ObservationCompositionReanalysisRequest) throws -> Data {
        var row = try ObservationHistorySyncTests().videoSnapshot()
        row["schema_version"] = 6
        row["observation_id"] = request.observationID.uuidString.lowercased()
        row["analysis_id"] = request.analysisID.uuidString.lowercased()
        row["source_analysis_id"] = request.sourceAnalysisID.uuidString.lowercased()
        row["request_digest"] = request.requestDigest
        row["evidence_manifest"] = try JSONSerialization.jsonObject(with: request.manifest.originalBytes)
        row["ordinal"] = 2
        var identification = try #require(row["result"] as? [String: Any])
        identification["scan_id"] = request.observationID.uuidString.lowercased()
        row["result"] = identification
        return try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    struct Context {
        let source: ObservationReanalysisSource
        let preparation: ObservationCompositionPreparation
        let container: ModelContainer
    }

    @MainActor final class Boundary {
        let seed: Context
        var events: [String] = []
        var hook: (String) throws -> Void = { _ in }
        var reply: ObservationAnalysisReceipt.State = .complete
        var bytes: Data?
        convenience init(_ seed: Seed) throws {
            try self.init(source: seed.source, preparation: seed.preparation, container: seed.container)
        }
        init(source: ObservationReanalysisSource, preparation: ObservationCompositionPreparation, container: ModelContainer) throws {
            seed = Context(source: source, preparation: preparation, container: container)
            bytes = try CompositionExecutionServiceTests().result(preparation.request)
        }
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
            }, synchronize: { [self] observation, container in
                #expect(observation == seed.preparation.identity.observationID && container === seed.container)
                try hit("synchronize")
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
        let (seed, saved) = try await seed(mode); defer { seed.removeFiles() }
        let proof = try seed.proof
        let boundary = try Boundary(seed)
        let status = try ObservationCompositionResumeStore.status(seed.preparation.identity, container: seed.container, isCurrent: { true })
        #expect(status.isComposition && status.canContinue == (mode == "idle"))
        #expect(status.canCheckOutcome == mode.contains("consumed"))
        try await owned(saved, seed) { scope, _ in
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup)
            #expect(outcome == (mode == "running" || mode == "held" ? .held : .completed))
        }
        #expect(boundary.events == (mode == "idle" ? ["authorize", "analyze", "outcome", "synchronize", "cleanup"]
            : mode.contains("consumed") ? ["outcome", "synchronize", "cleanup"] : []))
    }
    @Test(arguments: [false, true])
    func ambiguousConsumptionNeverInvokes(committed: Bool) async throws {
        let (seed, saved) = try await seed("idle"); defer { seed.removeFiles() }
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
        let (seed, saved) = try await seed("idle"); defer { seed.removeFiles() }
        let proof = try seed.proof
        let boundary = try Boundary(seed)
        try await owned(saved, seed) { scope, owner in
            if phase == "before" { if auth { owner.invalidate() } else { owner.cancel() } }
            boundary.hook = { if $0 == phase { if auth { owner.invalidate() } else { owner.cancel() } } }
            let result = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup)
            #expect(result == (auth || phase == "before" ? .unavailable : phase == "outcome" ? .completed : .held))
        }
        #expect(boundary.events.contains("cleanup") == (!auth && phase == "outcome"))
        #expect(!boundary.events.contains("synchronize"))
        if phase == "before" { #expect(boundary.events.isEmpty) }
        if phase == "authorize" { #expect(boundary.events == ["authorize"]) }
        if phase == "analyze" { #expect(!boundary.events.contains("outcome")) }
    }
    @Test(arguments: [ObservationAnalysisReceipt.State.admitted, .dispatched, .draft, .failedTerminal, .complete])
    func stateReceiptCannotReplaceExactResult(state: ObservationAnalysisReceipt.State) async throws {
        let (seed, saved) = try await seed("idle"); defer { seed.removeFiles() }
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
        let (seed, saved) = try await seed("running-consumed"); defer { seed.removeFiles() }
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
    @Test func projectionRefreshFailurePreservesCompletion() async throws {
        let (seed, saved) = try await seed("held-consumed"); defer { seed.removeFiles() }
        let proof = try seed.proof
        let boundary = try Boundary(seed)
        boundary.hook = { if $0 == "synchronize" { throw URLError(.notConnectedToInternet) } }
        try await owned(saved, seed) { scope, _ in
            #expect(await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup) == .completed)
        }
        #expect(boundary.events == ["outcome", "synchronize", "cleanup"])
    }

    @Test func preSyncedCompletionAndStaleSnapshotAreFenced() async throws {
        let (seed, saved) = try await seed("held-consumed"); defer { seed.removeFiles() }
        let proof = try seed.proof
        let boundary = try Boundary(seed), context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let bytes = try #require(boundary.bytes)
        let result = try ObservationReanalysisResult.decode(bytes, matching: saved.work.request)
        _ = try ObservationHistorySyncService.insert([result], into: parent, ownerID: seed.source.ownerID, context: context); try context.save()
        try await owned(saved, seed) { scope, _ in
            #expect(await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope, cleanup: boundary.cleanup) == .completed)
        }
        #expect(boundary.events == ["outcome", "synchronize", "cleanup"])
    }

    @Test func completionSelectsNewResultThenReplayPreservesLaterExplicitSelection() async throws {
        let (seed, saved) = try await seed("held-consumed"); defer { seed.removeFiles() }
        let proof = try seed.proof, owner = seed.source.ownerID, observation = seed.source.observationID.uuidString.lowercased()
        let first = seed.source.analysisID, second = UUID(), child = seed.preparation.identity.analysisID
        var value = try #require(JSONSerialization.jsonObject(with: result(saved.work.request)) as? [String: Any])
        value["ordinal"] = 3
        let completed = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        value["ordinal"] = 2; value["analysis_id"] = second.uuidString.lowercased()
        let older = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        let context = ModelContext(seed.container); context.autosaveEnabled = false
        let initial = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        initial.fieldNotes = "Private observation note"; initial.customTags = ["Private tag"]; try context.save()
        let initialState = try raceState(seed.source.snapshot, selected: first, revision: 11, owner: owner)
        _ = try await ObservationHistoryStateSyncService(cloud: raceCloud(owner: owner, state: initialState))
            .syncSelected(observationID: observation, container: seed.container)
        var outcomes = 0, refreshes = 0, receipts: [ObservationReanalysisErasureReceipt] = []
        let service = Service(dependencies: .init(authorize: { _, _ in
            Issue.record("Consumed work must not authorize again"); throw ObservationHistoryError.unavailable
        }, analyze: { _, _, _, _ in
            Issue.record("Consumed work must not invoke again"); throw ObservationHistoryError.unavailable
        }, outcome: { current, before, after in
            try before(); outcomes += 1
            #expect(current.work.attemptID == saved.work.attemptID && current.work.consumed)
            // A real selection transaction finishes while C's outcome read is suspended.
            try await raceSelect(older, target: second, previous: first, revision: 11,
                owner: owner, container: seed.container)
            try after(); return completed
        }, synchronize: { _, container in
            refreshes += 1
            let before = try #require(ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
            #expect(before.selectedAnalysisID == second.uuidString.lowercased())
            #expect(before.analysisRecords?.filter { $0.id == child.uuidString.lowercased() }.count == 1)
            let state = try raceState(completed, selected: child, revision: 13, owner: owner)
            _ = try await ObservationHistoryStateSyncService(cloud: raceCloud(owner: owner, state: state))
                .syncSelected(observationID: observation, container: container)
        }))
        try await owned(saved, seed) { scope, _ in
            #expect(await service.run(saved, proof: proof, container: seed.container, scope: scope,
                cleanup: { receipts.append($0) }) == .completed)
        }
        let current = try #require(ModelContext(seed.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(current.selectedAnalysisID == child.uuidString.lowercased() && current.observationStateRevision == 13)
        #expect(current.localAIIdentificationReview.authority == nil && current.userReviewState == .unreviewed)
        #expect(current.fieldNotes == "Private observation note" && current.customTags == ["Private tag"])
        #expect(outcomes == 1 && refreshes == 1 && receipts.count == 1)
        try await raceSelect(older, target: second, previous: child, revision: 13, owner: owner, container: seed.container)
        let replay = try Store.complete(saved, resultBytes: completed, proof: proof, container: seed.container, isCurrent: { true })
        #expect(replay == receipts.first)
        let final = try #require(ModelContext(seed.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(final.selectedAnalysisID == second.uuidString.lowercased() && final.observationStateRevision == 14)
        #expect(final.localAIIdentificationReview.authority?.state == .aiRejected)
        #expect(final.fieldNotes == "Private observation note" && final.customTags == ["Private tag"])
        #expect(final.analysisRecords?.count == 3)
        #expect(final.analysisRecords?.filter { $0.id == child.uuidString.lowercased() }.count == 1)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(outcomes == 1 && refreshes == 1 && receipts.count == 1)
    }

    private func raceState(_ snapshot: Data, selected: UUID, revision: Int, owner: UUID, rejected: Bool = false) throws -> Data {
        let result = try #require(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        let observation = try #require(result["observation_id"] as? String)
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = owner.uuidString.lowercased(); state["observation_id"] = observation
        state["selected_analysis_id"] = selected.uuidString.lowercased(); state["state_revision"] = revision
        var item = try #require(state["analysis"] as? [String: Any])
        item["snapshot"] = try #require(String(bytes: snapshot, encoding: .utf8))
        if rejected {
            var review = try #require(item["review_snapshot"] as? [String: Any])
            review["ai_identification_review"] = ["version": 1, "revision": 1, "state": "ai_rejected",
                "origin_scan_id": observation, "origin_identification": ["scientific_name": "Earlier result", "common_name": NSNull()],
                "operation_id": NSNull(), "operation_digest": NSNull(), "community": NSNull()] as [String: Any]
            item["review_snapshot"] = review; item["review_revision"] = 1
        }
        state["analysis"] = item
        return try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
    }

    private func raceCloud(owner: UUID, state: Data, previous: UUID? = nil) -> ObservationHistoryCloudClient {
        var cloud = ObservationHistoryCloudClient(begin: { expected in
            #expect(expected == owner)
            return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false))
        }, isCurrent: { $0.session.userID == owner }, finish: { _ in }, fetch: { _ in
            Issue.record("Selection must use authoritative state"); throw ObservationHistoryError.unavailable
        })
        cloud.fetchState = { _ in state }
        cloud.select = { request in
            try JSONEncoder().encode(ObservationHistorySelectionReceipt(schema_version: 1,
                operation_id: request.operation_id, observation_id: request.observation_id,
                previous_analysis_id: try #require(previous).uuidString.lowercased(), selected_analysis_id: request.analysis_id,
                observation_revision: request.expected_observation_revision + 1, review_revision: request.expected_review_revision))
        }
        return cloud
    }

    private func raceSelect(_ snapshot: Data, target: UUID, previous: UUID, revision: Int,
                            owner: UUID, container: ModelContainer) async throws {
        let value = try #require(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        let observation = try #require(value["observation_id"] as? String)
        let preview = try raceState(snapshot, selected: previous, revision: revision, owner: owner, rejected: true)
        _ = try await ObservationHistoryPreviewService(cloud: raceCloud(owner: owner, state: preview))
            .preview(observationID: observation, analysisID: target, container: container)
        let selected = try raceState(snapshot, selected: target, revision: revision + 1, owner: owner, rejected: true)
        let service = ObservationHistorySelectionService(cloud: raceCloud(owner: owner, state: selected, previous: previous))
        try service.prepare(observationID: observation, analysisID: target, ownerID: owner, container: container)
        _ = try await service.sendPending(observationID: observation, container: container)
    }
}
