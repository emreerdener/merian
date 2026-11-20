import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisAdvisoryTests {
    typealias Store = ObservationReanalysisAdmissionStore
    typealias Executor = ObservationReanalysisAdmissionExecutor
    let fixture = ObservationReanalysisRecoveryTests()
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func candidate(_ seed: ObservationReanalysisRecoveryTests.Seed) throws -> Store.Candidate {
        try #require(Store.candidates(ownerID: seed.pending.draft.identity.ownerID, canPreflight: true, now: now,
            container: seed.container, isCurrent: { true }).first)
    }
    func executor(_ seed: ObservationReanalysisRecoveryTests.Seed) -> Executor {
        let account = fixture.producerFixture.account()
        return Executor(files: .init(documents: seed.root), ownership: .init(), admission: .init(account: account,
            preflight: { _, _, validate in try validate(); return .init(recipient: .gemini, validate: validate) }), account: account, now: { now })
    }

    @Test func completeCohortPromotesWithoutConsentThenAdmitsSameChild() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed)
        let execute = executor(seed), first = try candidate(seed)
        #expect(try await execute.execute(first, container: seed.container, consentGranted: { false }, canPreflight: { false }, isCurrent: { true }) == .filesReady)
        let ready = try candidate(seed)
        #expect(ready.snapshot.work.preparation == first.snapshot.work.preparation)
        #expect(ready.snapshot.work.phase == .admissionPending)
        #expect(try await execute.execute(ready, container: seed.container, consentGranted: { false }, canPreflight: { true }, isCurrent: { true }) == .deferred)
        #expect(try Store.read(ready.snapshot.identity, container: seed.container, isCurrent: { true }) == ready.snapshot)
        #expect(try await execute.execute(ready, container: seed.container, consentGranted: { true }, canPreflight: { true }, isCurrent: { true }) == .admitted)
        let bound = try ObservationReanalysisExecutionStore.read(ready.snapshot.identity, container: seed.container, isCurrent: { true })
        #expect(bound.status == .pending && bound.attempt == 0 && bound.intent.request.evidence == seed.pending.draft.evidence)
        let parent = try #require(ModelContext(seed.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
    }

    @Test func missingNamespaceDoesNotClaimOrRewriteOriginalSubmission() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let initial = try candidate(seed)
        for _ in 0..<2 {
            #expect(try await executor(seed).execute(initial, container: seed.container, consentGranted: { false }, canPreflight: { false }, isCurrent: { true }) == .unclaimed)
            #expect(try Store.read(initial.snapshot.identity, container: seed.container, isCurrent: { true }) == initial.snapshot)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: seed.root.path).isEmpty)
    }

    @Test(arguments: ["missing", "digest"])
    func lockedIncompleteOrUncertainFilesWaitWithoutReadyPromotion(damage: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed)
        if damage == "missing" { try FileManager.default.removeItem(at: seed.file) } else { try Data(repeating: 0, count: seed.bytes.count).write(to: seed.file) }
        let initial = try candidate(seed)
        #expect(try await executor(seed).execute(initial, container: seed.container, consentGranted: { true }, canPreflight: { true }, isCurrent: { true }) == .waiting)
        let saved = try Store.read(initial.snapshot.identity, container: seed.container, isCurrent: { true })
        #expect(saved.work.phase == .filesPending && saved.work.state == .waiting && saved.work.attempt == 1)
        #expect(saved.work.preparation == initial.snapshot.work.preparation)
    }

    @Test(arguments: ["recovery", "consent", "network", "stale", "account", "delete"])
    func preflightOutcomesPreserveClaimsAndExplicitConsentRearm(reason: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed); _ = try await fixture.recover(seed)
        let initial = try candidate(seed)
        var current = true, consent = true, online = true
        var execute = executor(seed)
        execute.admission.preflight = { _, _, validate in
            switch reason {
            case "consent": consent = false
            case "network": online = false
            case "account": current = false
            case "stale":
                let saved = try Store.read(initial.snapshot.identity, container: seed.container, isCurrent: { true })
                _ = try Store.claim(saved, admission: .interrupted, now: now, container: seed.container, isCurrent: { true })
            case "delete":
                let context = ModelContext(seed.container)
                _ = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString, context: context)
                try context.save()
            default: break
            }
            try validate()
            return .init(recipient: .recoveryOnly, validate: validate)
        }
        if ["stale", "account", "delete"].contains(reason) {
            await #expect(throws: (any Error).self) {
                try await execute.execute(initial, container: seed.container, consentGranted: { consent }, canPreflight: { online }, isCurrent: { current })
            }
        } else {
            let outcome = try await execute.execute(initial, container: seed.container, consentGranted: { consent }, canPreflight: { online }, isCurrent: { current })
            #expect(outcome == (reason == "network" ? .waiting : .held(reason == "consent" ? .consentRequired : .reconciliationRequired)))
            let saved = try Store.read(initial.snapshot.identity, container: seed.container, isCurrent: { true })
            if reason != "network" {
                #expect(saved.work.due(now: now, canPreflight: true) == nil)
                #expect(throws: (any Error).self) { try Store.rearmConsent(saved, now: now, container: seed.container, isCurrent: { true }, consentGranted: { false }) }
                if reason == "consent" {
                    let rearmed = try Store.rearmConsent(saved, now: now, container: seed.container, isCurrent: { true }, consentGranted: { true })
                    #expect(rearmed.work.attempt == saved.work.attempt && rearmed.work.preparation == saved.work.preparation)
                    #expect(rearmed.work.state == .waiting && rearmed.work.due(now: now, canPreflight: false) == nil)
                    #expect(throws: (any Error).self) { try Store.rearmConsent(saved, now: now, container: seed.container, isCurrent: { true }, consentGranted: { true }) }
                } else {
                    #expect(throws: (any Error).self) { try Store.rearmConsent(saved, now: now, container: seed.container, isCurrent: { true }, consentGranted: { true }) }
                }
            }
        }
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: initial.snapshot.identity.ownerID, container: seed.container, isCurrent: { true }).isEmpty)
    }

    @Test func changedSourceCannotCommitLockedClaim() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed)
        let initial = try candidate(seed), proof = try seed.pending.verified(source: seed.source)
        var reachedRead = false
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisFileStore(documents: seed.root).recover(draft: seed.pending.draft, validateBeforeRead: {
                let context = ModelContext(seed.container)
                let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
                let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
                let replacement = try LocalAnalysisRecord(analysisID: seed.source.analysisID, observationID: parent.id,
                    ownerAccountID: seed.source.ownerID, completedAt: record.completedAt, snapshotVersion: record.snapshotVersion,
                    resultSnapshotData: JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: record.resultSnapshotData), options: [.prettyPrinted, .sortedKeys]))
                context.delete(record); try context.save(); context.insert(replacement); parent.analysisRecords = [replacement]; try context.save()
                _ = try Store.claim(initial.snapshot, admission: .initial, now: now, container: seed.container, isCurrent: { true }, proof: proof)
                reachedRead = true
            }) { Issue.record("Changed source authorized file completion") }
        }
        #expect(!reachedRead)
        #expect(try Store.read(initial.snapshot.identity, container: seed.container, isCurrent: { true }) == initial.snapshot)
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test func interruptedTenthAdmissionDoesNotStartAnotherPreflight() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed); _ = try await fixture.recover(seed)
        var saved = try candidate(seed).snapshot
        for attempt in 0..<10 {
            saved = try Store.claim(saved, admission: attempt == 0 ? .initial : .interrupted,
                now: now, container: seed.container, isCurrent: { true }).snapshot
        }
        var execute = executor(seed), calls = 0
        execute.admission.preflight = { _, _, _ in calls += 1; throw MerianError.invalidResponse }
        #expect(try await execute.execute(candidate(seed), container: seed.container, consentGranted: { true }, canPreflight: { true }, isCurrent: { true }) == .held(.retryLimit))
        #expect(calls == 0)
    }

}
