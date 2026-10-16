import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisSubmissionTests {
    typealias Persistence = ObservationReanalysisPersistence
    typealias Store = ObservationReanalysisExecutionStore
    let fixture = ObservationReanalysisRecoveryTests()

    @Test(arguments: [false, true])
    func sourceAndSubmitDispositionSurvivePreparationCrashAndDiskRestart(submitted: Bool) async throws {
        let directory = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let pending: ObservationReanalysisPreparationIntent, root: URL
        do {
            let seed = try fixture.seed(action: submitted ? .submit : .hold, url: url)
            pending = seed.pending; root = seed.root
            await #expect(throws: (any Error).self) { try await fixture.recover(seed) }
            try fixture.expectPending(seed) // Before any complete file cohort: no phase promotion.
            try await fixture.publish(seed) // Crash after bytes, before ready CAS.
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try fixture.sourceFixture.fixture.container(url: url, seed: false)
        let recovery = ObservationReanalysisPreparationRecovery(files: .init(documents: root), ownership: .init(), account: fixture.producerFixture.account())
        let result = try await recovery.recover(pending.draft.identity, container: container, isCurrent: { true })
        if submitted {
            guard case let .submitted(saved) = result else { Issue.record("Submission became a held draft"); return }
            #expect(saved.preparation == pending)
            #expect(try ObservationReanalysisSubmissionIntent.decode(saved.storedData()) == saved)
        } else {
            guard case let .draft(saved) = result else { Issue.record("Legacy draft became submitted"); return }
            #expect(saved == pending.draft)
        }
        #expect(try Store.candidates(ownerID: pending.draft.identity.ownerID, container: container, isCurrent: { true }).isEmpty)
        let context = ModelContext(container), parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == pending.draft.identity.sourceAnalysisID.uuidString.lowercased())
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(job.status == .needsAttention && job.attemptCount == 0 && job.nextRunAt == nil)
    }

    @Test(arguments: ["extra", "action", "legacy-action", "boolean-version", "digest", "phase"])
    func preparationAndReadyEnvelopesAreClosed(damage: String) throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        for bytes in [try seed.pending.storedData(), try seed.pending.readyData()] {
            var row = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            switch damage {
            case "extra": row["extra"] = true
            case "action": row["requested_action"] = "save"
            case "legacy-action": row["version"] = 3
            case "boolean-version": row["version"] = true
            case "digest": row["source_snapshot_sha256"] = "invalid"
            default: row["phase"] = "unknown"
            }
            let invalid = try JSONSerialization.data(withJSONObject: row)
            #expect(throws: (any Error).self) { try ObservationReanalysisPreparationIntent.decode(invalid) }
            #expect(throws: (any Error).self) { try ObservationReanalysisSubmissionIntent.decode(invalid) }
        }
    }

    @Test func staleHeldPreparationCannotDowngradeSubmissionAndSaveFailureKeepsOriginalPhase() throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let held = try ObservationReanalysisPreparationIntent(draft: seed.pending.draft, source: seed.source)
        for ready in [false, true] {
            if ready {
                #expect(throws: (any Error).self) {
                    try Persistence.validatePreparation(seed.pending.verified(source: seed.source), container: seed.container,
                        isCurrent: { true }, makeReady: true, save: { _ in throw CocoaError(.fileWriteUnknown) })
                }
                try fixture.expectPending(seed)
                try Persistence.validatePreparation(seed.pending.verified(source: seed.source), container: seed.container,
                    isCurrent: { true }, makeReady: true)
            }
            #expect(throws: (any Error).self) {
                try Persistence.beginPreparation(held.verified(source: seed.source), container: seed.container, isCurrent: { true })
            }
        }
        #expect(throws: (any Error).self) {
            try Persistence.bindDraft(seed.pending.draft, processor: .gemini, container: seed.container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) {
            try Store.bindAndAdmit(seed.pending.draft, processor: .gemini, now: Date(), container: seed.container, isCurrent: { true })
        }
    }

    @Test(arguments: ["ready", "recovery", "consent", "account", "discard", "source-digest"])
    func submissionRequiresExactSourceAndCurrentPermissionBeforeBinding(outcome: String) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed); _ = try await fixture.recover(seed)
        var current = true, preflights = 0
        if outcome == "source-digest" {
            let context = ModelContext(seed.container), job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
            let metadata = try #require(job.metadataJSON)
            var row = try #require(JSONSerialization.jsonObject(with: Data(metadata.utf8)) as? [String: Any])
            row["source_snapshot_sha256"] = String(repeating: "0", count: 64)
            job.metadataJSON = String(bytes: try JSONSerialization.data(withJSONObject: row), encoding: .utf8); try context.save()
        }
        let admission = ObservationReanalysisAdmission(account: fixture.producerFixture.account(current: { current }),
            preflight: { input, _, validate in
                preflights += 1; try validate()
                #expect(input.analysisID == seed.pending.draft.identity.analysisID)
                if outcome == "consent" { throw MerianError.aiConsentRequired }
                if outcome == "account" { current = false }
                if outcome == "discard" {
                    _ = try Persistence.discardPreparation(source: seed.source, analysisID: seed.pending.draft.identity.analysisID,
                        container: seed.container, isCurrent: { true })
                }
                return .init(recipient: outcome == "recovery" ? .recoveryOnly : .gemini, validate: validate)
            })
        if outcome == "ready" {
            let result = try await admission.admit(seed.pending.draft, container: seed.container, isCurrent: { true })
            #expect(result.status == .pending && result.intent.request.evidence == seed.pending.draft.evidence)
            #expect(throws: (any Error).self) {
                try Persistence.discardPreparation(source: seed.source, analysisID: seed.pending.draft.identity.analysisID,
                    container: seed.container, isCurrent: { true })
            }
        } else {
            await #expect(throws: (any Error).self) {
                try await admission.admit(seed.pending.draft, container: seed.container, isCurrent: { true })
            }
            #expect(try Store.candidates(ownerID: seed.source.ownerID, container: seed.container, isCurrent: { true }).isEmpty)
            if outcome != "discard" {
                guard case .ready(.submitted) = try Persistence.preparation(seed.pending.draft.identity,
                    container: seed.container, isCurrent: { true }) else { Issue.record("Submission intent was lost"); return }
            }
        }
        #expect(preflights == (outcome == "source-digest" ? 0 : 1))
    }

    @Test(arguments: [false, true])
    func discardFencesSubmittedPreparationAndReadyRecovery(ready: Bool) async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed)
        if ready { _ = try await fixture.recover(seed) }
        let receipt = try Persistence.discardPreparation(source: seed.source, analysisID: seed.pending.draft.identity.analysisID,
            container: seed.container, isCurrent: { true })
        await #expect(throws: (any Error).self) { try await fixture.recover(seed) }
        #expect(throws: (any Error).self) {
            try Persistence.beginPreparation(seed.pending.verified(source: seed.source), container: seed.container, isCurrent: { true })
        }
        let context = ModelContext(seed.container)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        let retained = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.pending.draft.identity.analysisID))
        let saved = try #require(retained)
        #expect(try ObservationReanalysisErasureReceipt.restore(saved) == receipt)
    }

    @Test func suspendedPreflightCannotDispatchAfterConcurrentDiscard() async throws {
        let seed = try fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        try await fixture.publish(seed); _ = try await fixture.recover(seed)
        let entered = AsyncStream<Void>.makeStream(), resume = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); resume.continuation.finish() }
        var dispatched = false
        let admission = ObservationReanalysisAdmission(account: fixture.producerFixture.account(), preflight: { _, _, validate in
            entered.continuation.yield()
            for await _ in resume.stream { break }
            try validate()
            dispatched = true
            return .init(recipient: .gemini, validate: validate)
        })
        let task = Task { try await admission.admit(seed.pending.draft, container: seed.container, isCurrent: { true }) }
        for await _ in entered.stream { break }
        let receipt = try Persistence.discardPreparation(source: seed.source, analysisID: seed.pending.draft.identity.analysisID,
            container: seed.container, isCurrent: { true })
        resume.continuation.yield()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(!dispatched)
        let context = ModelContext(seed.container)
        let retained = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.pending.draft.identity.analysisID))
        let saved = try #require(retained)
        #expect(try ObservationReanalysisErasureReceipt.restore(saved) == receipt)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }
}
