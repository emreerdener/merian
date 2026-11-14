import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisAdmissionWorkTests {
    typealias Store = ObservationReanalysisAdmissionStore
    typealias Work = ObservationReanalysisAdmissionWork
    typealias Persistence = ObservationReanalysisPersistence
    let fixture = ObservationReanalysisRecoveryTests()
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test(arguments: [false, true])
    func onlySubmittedWorkIsEligibleAndConsentFiltersOnlyReadyPhase(ready: Bool) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        if ready { try await fixture.publish(seed); _ = try await fixture.recover(seed) }
        let identity = seed.pending.draft.identity
        let snapshot = try Store.read(identity, container: seed.container, isCurrent: { true })
        #expect(snapshot.work.phase == (ready ? .admissionPending : .filesPending))
        #expect(try Work.decode(snapshot.work.storedData()) == snapshot.work)
        for allowed in [false, true] {
            let candidates = try Store.candidates(ownerID: identity.ownerID, canPreflight: allowed, now: now,
                container: seed.container, isCurrent: { true })
            #expect(candidates.count == (ready && !allowed ? 0 : 1))
        }
        #expect(try Store.candidates(ownerID: UUID(), canPreflight: true, now: now, container: seed.container, isCurrent: { true }).isEmpty)
        let held = try ObservationReanalysisPreparationIntent(draft: seed.pending.draft, source: seed.source)
        for data in [try held.storedData(), try held.readyData()] {
            #expect(throws: (any Error).self) { try Work.decode(data) }
        }
    }

    @Test(arguments: ["extra", "phase", "version", "boolean-attempt", "fractional-attempt", "date", "hold", "state", "nested-held"])
    func wrapperRejectsMalformedState(damage: String) throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let work = try Work(preparation: seed.pending, phase: .filesPending)
        var row = try #require(JSONSerialization.jsonObject(with: work.storedData()) as? [String: Any])
        switch damage {
        case "extra": row["extra"] = true
        case "phase": row["phase"] = "ready"
        case "version": row["version"] = true
        case "boolean-attempt": row["attempt"] = false
        case "fractional-attempt": row["attempt"] = 0.5
        case "date": row["updated_at"] = "later"
        case "hold": row["hold"] = "consentRequired"
        case "state": row["state"] = "running"
        default:
            let held = try ObservationReanalysisPreparationIntent(draft: seed.pending.draft, source: seed.source)
            row["preparation"] = try JSONSerialization.jsonObject(with: held.storedData())
        }
        let invalid = try JSONSerialization.data(withJSONObject: row)
        #expect(throws: (any Error).self) { try Work.decode(invalid) }
    }

    @Test func claimsRetryAndHoldsNeverMutateExecutionFieldsOrAllowStaleCompletion() throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let identity = seed.pending.draft.identity
        let initial = try Store.read(identity, container: seed.container, isCurrent: { true })
        let first = try Store.claim(initial, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.claim(initial, admission: .initial, now: now, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.settle(first, as: .held(.retryLimit), now: now, container: seed.container, isCurrent: { true },
                save: { _ in throw CocoaError(.fileWriteUnknown) })
        }
        #expect(try Store.validate(first, container: seed.container, isCurrent: { true }) == first.snapshot)
        try Store.settle(first, as: .waiting(now.addingTimeInterval(30)), now: now, container: seed.container, isCurrent: { true })
        let waiting = try Store.read(identity, container: seed.container, isCurrent: { true })
        #expect(waiting.work.phase == .filesPending && waiting.work.attempt == 1)
        #expect(throws: (any Error).self) { try Store.claim(waiting, admission: .dueRetry, now: now, container: seed.container, isCurrent: { true }) }
        let retry = try Store.claim(waiting, admission: .dueRetry, now: now.addingTimeInterval(30), container: seed.container, isCurrent: { true })
        #expect(retry.snapshot.work.attempt == 2)
        #expect(throws: (any Error).self) { try Store.settle(first, as: .held(.retryLimit), now: now, container: seed.container, isCurrent: { true }) }
        try Store.settle(retry, as: .held(.reconciliationRequired), now: now.addingTimeInterval(31), container: seed.container, isCurrent: { true })
        #expect(try Store.candidates(ownerID: identity.ownerID, canPreflight: true, now: now, container: seed.container, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: identity.ownerID, container: seed.container, isCurrent: { true }).isEmpty)
        let context = ModelContext(seed.container), job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let queued = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        #expect(job.attemptCount == 0 && job.status == .needsAttention && job.nextRunAt == nil)
        #expect(queued.queueAttemptCount == 0 && queued.queueNeedsAttention && queued.queueNextRetryAt == nil)
        _ = try Persistence.discardPreparation(source: seed.source, analysisID: identity.analysisID, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.validate(retry, container: seed.container, isCurrent: { true }) }
    }

    @Test func onlyVerifiedLockedFilesPromoteAndStaleClaimCannotSettleNewPhase() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let identity = seed.pending.draft.identity, proof = try seed.pending.verified(source: seed.source)
        let initial = try Store.read(identity, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(initial, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        let files = ObservationReanalysisFileStore(documents: seed.root)
        let verify: @MainActor @Sendable () throws -> Void = {
            try Store.validate(claim, container: seed.container, isCurrent: { true }, proof: proof)
        }
        let promote: @MainActor @Sendable () throws -> Store.Snapshot = {
            try Store.promoteVerifiedFiles(claim, proof: proof, container: seed.container, isCurrent: { true })
        }
        await #expect(throws: (any Error).self) { try await files.recover(draft: seed.pending.draft, validateBeforeRead: verify, commit: promote) }
        #expect(try Store.validate(claim, container: seed.container, isCurrent: { true }).work.phase == .filesPending)
        try await fixture.publish(seed)
        let ready = try await files.recover(draft: seed.pending.draft, validateBeforeRead: verify, commit: promote)
        #expect(ready.work.phase == .admissionPending && ready.work.preparation == seed.pending)
        #expect(ready.work.due(now: now, canPreflight: false) == nil)
        #expect(throws: (any Error).self) { try Store.settle(claim, as: .held(.retryLimit), now: now, container: seed.container, isCurrent: { true }) }
    }

    @Test(arguments: ["success", "stale", "account", "files", "recovery"])
    func admissionRequiresLiveReadyClaimAcrossPreflight(outcome: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        if outcome != "files" { try await fixture.publish(seed); _ = try await fixture.recover(seed) }
        let identity = seed.pending.draft.identity
        let initial = try Store.read(identity, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(initial, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        var current = true, calls = 0
        let admission = ObservationReanalysisAdmission(account: fixture.producerFixture.account(current: { current }), preflight: { _, _, validate in
            calls += 1
            if outcome == "stale" { _ = try Store.claim(claim.snapshot, admission: .interrupted, now: now, container: seed.container, isCurrent: { true }) }
            if outcome == "account" { current = false }
            try validate()
            return .init(recipient: outcome == "recovery" ? .recoveryOnly : .gemini, validate: validate)
        })
        #expect(throws: (any Error).self) {
            try Persistence.discardPreparation(source: seed.source, analysisID: identity.analysisID, container: seed.container, isCurrent: { true })
        }
        if outcome == "success" {
            let bound = try await admission.admit(seed.pending.draft, container: seed.container, admissionClaim: claim, isCurrent: { true })
            #expect(bound.status == .pending && bound.attempt == 0 && bound.intent.request.evidence == seed.pending.draft.evidence)
            #expect(throws: (any Error).self) { try Store.validate(claim, container: seed.container, isCurrent: { true }) }
        } else {
            await #expect(throws: (any Error).self) {
                try await admission.admit(seed.pending.draft, container: seed.container, admissionClaim: claim, isCurrent: { true })
            }
            #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: identity.ownerID, container: seed.container, isCurrent: { true }).isEmpty)
        }
        #expect(calls == (outcome == "files" ? 0 : 1))
    }

    @Test func interruptedClaimSurvivesDiskRestartAndBindingSaveFailureRetainsWrapper() async throws {
        let directory = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let previous: Store.Claim, proof: ObservationReanalysisPreparationIntent.Verified
        do {
            let seed = try fixture.seed(action: .submit, url: url)
            defer { try? FileManager.default.removeItem(at: seed.root) }
            try await fixture.publish(seed); _ = try await fixture.recover(seed)
            proof = try seed.pending.verified(source: seed.source)
            let initial = try Store.read(seed.pending.draft.identity, container: seed.container, isCurrent: { true })
            previous = try Store.claim(initial, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        }
        let container = try fixture.sourceFixture.fixture.container(url: url, seed: false)
        let saved = try Store.read(previous.snapshot.identity, container: container, isCurrent: { true })
        #expect(saved == previous.snapshot)
        let recovered = try Store.claim(saved, admission: .interrupted, now: now.addingTimeInterval(1), container: container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.validate(previous, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisExecutionStore.bindAndAdmit(proof.pending.draft, processor: .gemini, now: now,
                container: container, isCurrent: { true }, submissionProof: proof, admissionClaim: recovered,
                save: { _ in throw CocoaError(.fileWriteUnknown) })
        }
        #expect(try Store.validate(recovered, container: container, isCurrent: { true }) == recovered.snapshot)
        let bound = try ObservationReanalysisExecutionStore.bindAndAdmit(proof.pending.draft, processor: .gemini, now: now,
            container: container, isCurrent: { true }, submissionProof: proof, admissionClaim: recovered)
        #expect(bound.status == .pending && bound.attempt == 0)
    }

    @Test func fractionalEpochDatesUsePersistedPrecisionForClaimAndRetryCAS() throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let fractional = Date(timeIntervalSinceReferenceDate: 800_000_000.0000001)
        #expect(fractional != Date(timeIntervalSince1970: fractional.timeIntervalSince1970))
        let identity = seed.pending.draft.identity
        let initial = try Store.read(identity, container: seed.container, isCurrent: { true })
        let claim = try Store.claim(initial, admission: .initial, now: fractional, container: seed.container, isCurrent: { true })
        #expect(try Store.validate(claim, container: seed.container, isCurrent: { true }) == claim.snapshot)
        let due = fractional.addingTimeInterval(30)
        try Store.settle(claim, as: .waiting(due), now: fractional, container: seed.container, isCurrent: { true })
        let waiting = try Store.read(identity, container: seed.container, isCurrent: { true })
        #expect(waiting.work.nextRetryAt == Date(timeIntervalSince1970: due.timeIntervalSince1970))
        let retry = try Store.claim(waiting, admission: .dueRetry, now: due.addingTimeInterval(1), container: seed.container, isCurrent: { true })
        #expect(try Store.validate(retry, container: seed.container, isCurrent: { true }) == retry.snapshot)
    }

}
