import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioExecutionServiceTests {
    typealias Store = ObservationAudioExecutionStore
    typealias Seed = ObservationAudioPreparationTests.Seed
    typealias Service = ObservationAudioExecutionService
    let fixture = ObservationAudioExecutionStoreTests()

    @MainActor final class Boundary {
        let seed: Seed
        var events: [String] = []
        var hook: (String) throws -> Void = { _ in }
        var reply: ObservationAnalysisReceipt.State = .complete
        var bytes: Data?
        init(_ seed: Seed) throws { self.seed = seed; bytes = try ObservationAudioCompletionTests().result(seed) }
        func hit(_ phase: String) throws { events.append(phase); try hook(phase) }
        var service: Service {
            Service(dependencies: .init(read: { [self] preparation, before, after in
                try hit("read")
                return try await ObservationReanalysisFileStore(documents: seed.root).readAudio(preparation: preparation,
                    validateBeforeRead: before, validateBeforeReturn: after)
            }, upload: { [self] upload, owner, validate in
                try validate(); try hit("upload"); #expect(owner == seed.source.ownerID)
                let prepared = try upload.prepare()
                #expect(prepared.reference == seed.preparation.audio)
                return .init(observationID: upload.observationID, analysisID: upload.analysisID, reference: prepared.reference)
            }, authorize: { [self] owner, validate in
                try validate(); try hit("authorize"); #expect(owner == seed.source.ownerID)
                return IdentificationDispatchAuthorization(recipient: .gemini, validate: {})
            }, analyze: { [self] permit, _, before, after in
                try before(); try hit("analyze"); try after()
                return .init(observationID: permit.snapshot.work.intent.identity.observationID,
                    analysisID: permit.snapshot.work.intent.identity.analysisID, state: reply)
            }, outcome: { [self] claim, before, after in
                try before(); #expect(claim.snapshot.work.consumedAttempt != nil)
                try hit("outcome"); try after(); return bytes
            }, cleanup: { [self] receipt in
                #expect(receipt.childID == seed.preparation.identity.analysisID)
                events.append("cleanup")
            }))
        }
    }

    func entry(_ seed: Seed, mode: String) throws -> Store.Snapshot {
        let initial = try fixture.bind(seed)
        if mode == "initial" { return initial }
        let claim = try Store.claim(initial, purpose: .initial, proof: seed.proof, container: seed.container, isCurrent: { true })
        let active = mode.contains("Consumed") || mode == "consumed"
            ? try Store.consume(claim, proof: seed.proof, container: seed.container, isCurrent: { true }).claim : claim
        if mode.hasPrefix("running") { return active.snapshot }
        try Store.hold(active, proof: seed.proof, container: seed.container, isCurrent: { true })
        return try Store.read(seed.proof, container: seed.container, isCurrent: { true })
    }

    @Test(arguments: ["initial", "held", "running", "consumed", "runningConsumed"])
    func exactOrderingAndAppendOnlyCompletion(mode: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try entry(seed, mode: mode), boundary = try Boundary(seed), proof = try seed.proof
        let before = try ModelContext(seed.container).fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID
        try await ObservationAudioInterruptionTests().owned(saved, seed: seed) { scope, _ in
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope)
            #expect(outcome == .completed)
        }
        let expected = saved.work.consumedAttempt != nil ? ["outcome", "cleanup"]
            : (mode == "initial" ? [] : ["authorize"]) + ["read", "upload", "authorize", "analyze", "outcome", "cleanup"]
        #expect(boundary.events == expected)
        let context = ModelContext(seed.container)
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID == before)
        #expect(try context.fetch(FetchDescriptor<LocalAnalysisRecord>()).count == 2)
    }

    @Test(arguments: [false, true])
    func uncertainConsumeNeverAnalyzes(committed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try entry(seed, mode: "initial"), boundary = try Boundary(seed), proof = try seed.proof
        var service = boundary.service
        service.consumeSave = { if committed { try $0.save() }; throw CocoaError(.fileWriteUnknown) }
        let executor = service
        try await ObservationAudioInterruptionTests().owned(saved, seed: seed) { scope, owner in
            let outcome = await executor.run(saved, proof: proof, container: seed.container, scope: scope)
            #expect(outcome == .held); owner.cancel()
        }
        #expect(boundary.events == ["read", "upload", "authorize"])
        let held = try Store.read(proof, container: seed.container, isCurrent: { true })
        #expect(held.work.state == .held && held.work.intent == saved.work.intent)
        #expect(held.work.consumedAttempt == (committed ? 1 : nil))
    }

    @Test(arguments: ["read", "upload", "authorize", "analyze"])
    func boundaryFailureHoldsWithoutReplay(phase: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try entry(seed, mode: "initial"), boundary = try Boundary(seed), proof = try seed.proof
        boundary.hook = { if $0 == phase { throw URLError(.timedOut) } }
        try await ObservationAudioInterruptionTests().owned(saved, seed: seed) { scope, _ in
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope)
            #expect(outcome == .held)
        }
        let held = try Store.read(proof, container: seed.container, isCurrent: { true })
        #expect(held.work.consumedAttempt == (phase == "analyze" ? 1 : nil))
        #expect(!boundary.events.contains("outcome") && !boundary.events.contains("cleanup"))
    }

    @Test(arguments: ["cancel", "account", "deleted", "missing", "malformed"])
    func outcomeSettlementRetainsExactScope(reason: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try entry(seed, mode: "consumed"), boundary = try Boundary(seed), proof = try seed.proof
        if reason == "missing" { boundary.bytes = nil }
        if reason == "malformed" { boundary.bytes = Data("{}".utf8) }
        try await ObservationAudioInterruptionTests().owned(saved, seed: seed) { scope, owner in
            boundary.hook = { phase in
                guard phase == "outcome" else { return }
                if reason == "cancel" { owner.cancel() }
                if reason == "account" { owner.invalidate() }
                if reason == "deleted" {
                    let context = ModelContext(seed.container)
                    let rows = try context.fetch(FetchDescriptor<LocalScanRecord>())
                    context.delete(try #require(rows.first)); try context.save()
                }
            }
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope)
            #expect(outcome == (reason == "cancel" ? .completed : (reason == "account" || reason == "deleted" ? .unavailable : .held)))
        }
        #expect(boundary.events == (reason == "cancel" ? ["outcome", "cleanup"] : ["outcome"]))
    }

    @Test(arguments: [ObservationAnalysisReceipt.State.admitted, .dispatched, .draft, .failedTerminal, .complete])
    func dispatchReceiptNeverSubstitutesForOutcome(state: ObservationAnalysisReceipt.State) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try entry(seed, mode: "initial"), boundary = try Boundary(seed), proof = try seed.proof
        boundary.reply = state; boundary.bytes = nil
        try await ObservationAudioInterruptionTests().owned(saved, seed: seed) { scope, _ in
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope)
            #expect(outcome == .held)
        }
        #expect(boundary.events.filter { $0 == "analyze" }.count == 1)
        #expect(boundary.events.contains("outcome") == (state == .complete))
        #expect(!boundary.events.contains("cleanup"))
    }

    @Test func staleEntryHasNoSideEffectsAndResumeDenialDoesNotReadFiles() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try entry(seed, mode: "held"), boundary = try Boundary(seed), proof = try seed.proof
        try await ObservationAudioInterruptionTests().owned(saved, seed: seed) { scope, _ in
            boundary.hook = { _ in throw MerianError.aiConsentRequired }
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope)
            #expect(outcome == .held && boundary.events == ["authorize"])
            let later = try Store.resumeUndispatched(saved, proof: proof, authorization: fixture.authorization,
                container: seed.container, isCurrent: { true })
            boundary.events = []
            let stale = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope)
            let mismatched = await boundary.service.run(later.snapshot, proof: proof, container: seed.container, scope: scope)
            #expect(stale == .unavailable && mismatched == .unavailable && boundary.events.isEmpty)
        }
    }

    @Test func cancellationAfterDispatchReceiptHoldsWithoutStartingOutcomeRead() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try entry(seed, mode: "initial"), boundary = try Boundary(seed), proof = try seed.proof
        try await ObservationAudioInterruptionTests().owned(saved, seed: seed) { scope, owner in
            boundary.hook = { if $0 == "analyze" { owner.cancel() } }
            let outcome = await boundary.service.run(saved, proof: proof, container: seed.container, scope: scope)
            #expect(outcome == .held)
        }
        #expect(boundary.events == ["read", "upload", "authorize", "analyze"])
        #expect(try Store.read(proof, container: seed.container, isCurrent: { true }).work.consumedAttempt == 1)
    }

}
