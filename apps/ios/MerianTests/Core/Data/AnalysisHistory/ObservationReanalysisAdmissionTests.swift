import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisAdmissionTests {
    typealias Store = ObservationReanalysisExecutionStore
    let fixture = ObservationReanalysisExecutionTests()
    func draft() throws -> ObservationReanalysisDraft {
        let intent = try fixture.fixture.intent()
        return try .init(identity: intent.identity, evidence: intent.request.evidence)
    }
    func stage(_ container: ModelContainer) throws -> ObservationReanalysisDraft {
        let draft = try draft()
        _ = try ObservationReanalysisPersistence.stageDraft(draft, container: container, isCurrent: { true })
        return draft
    }
    func admit(_ draft: ObservationReanalysisDraft, _ container: ModelContainer) throws -> Store.Snapshot {
        try Store.bindAndAdmit(draft, processor: .gemini, now: fixture.now, container: container, isCurrent: { true })
    }
    @Test func admissionIsAtomicAndSurvivesDiskRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("store.sqlite")
        let pending: Store.Snapshot
        do {
            let container = try fixture.fixture.fixture.container(url: url), draft = try stage(container)
            #expect(throws: (any Error).self) { try Store.read(draft.identity, container: container, isCurrent: { true }) }
            #expect(try Store.candidates(ownerID: draft.identity.ownerID, container: container, isCurrent: { true }).isEmpty)
            pending = try admit(draft, container)
            #expect(pending.status == .pending && pending.attempt == 0 && pending.nextRun == fixture.now)
            let (context, row, job) = try fixture.fixture.stored(container)
            #expect(!row.queueNeedsAttention && row.queueUpdatedAt == job.updatedAt && !row.permitsOrdinaryInference)
            #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.observationStateRevision == 3)
        }
        let reopened = try fixture.fixture.fixture.container(url: url, seed: false)
        let candidate = try #require(Store.candidates(ownerID: pending.intent.ownerID, container: reopened, isCurrent: { true }).first)
        #expect(candidate.snapshot == pending && candidate.due == fixture.now)
        let claim = try Store.claim(candidate.snapshot, admission: candidate.admission, now: fixture.now, container: reopened, isCurrent: { true })
        #expect(claim.snapshot.attempt == 1 && claim.intent == pending.intent)
    }
    @Test func pristineHeldBoundRequestNeedsExplicitAdmissionAndFuturePendingCannotRunEarly() throws {
        let container = try fixture.fixture.fixture.container(); _ = try fixture.fixture.stage(container)
        let held = try Store.read(draft().identity, container: container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.claim(held, admission: .initial, now: fixture.now, container: container, isCurrent: { true }) }
        let pending = try admit(draft(), container)
        #expect(throws: (any Error).self) {
            try Store.claim(pending, admission: .initial, now: fixture.now.addingTimeInterval(-1), container: container, isCurrent: { true })
        }
    }
    @Test(arguments: ["pending", "running", "waiting", "held"])
    func exactAdmissionReplayNeverReschedulesOrRevives(_ phase: String) throws {
        let container = try fixture.fixture.fixture.container(), draft = try stage(container)
        let pending = try admit(draft, container)
        if phase != "pending" {
            let claim = try Store.claim(pending, admission: .initial, now: fixture.now, container: container, isCurrent: { true })
            if phase == "waiting" {
                let dispatched = try Store.consumeDispatch(claim, container: container, isCurrent: { true })
                try Store.settle(dispatched, as: .waiting(until: fixture.now.addingTimeInterval(30), server: .dispatched), now: fixture.now,
                    container: container, isCurrent: { true })
            } else if phase == "held" {
                try Store.settle(claim, as: .held(.consentRequired), now: fixture.now, container: container, isCurrent: { true })
            }
        }
        let saved = try Store.read(draft.identity, container: container, isCurrent: { true })
        #expect(try Store.bindAndAdmit(draft, processor: .gemini, now: fixture.now.addingTimeInterval(60),
            container: container, isCurrent: { true }) == saved)
        #expect(throws: (any Error).self) {
            try Store.bindAndAdmit(draft, processor: .openAI, now: fixture.now, container: container, isCurrent: { true })
        }
    }
    @Test func failedAdmissionSaveLeavesOriginalUnboundDraftAndNoWake() throws {
        let container = try fixture.fixture.fixture.container(), draft = try stage(container)
        #expect(throws: (any Error).self) {
            try Store.bindAndAdmit(draft, processor: .gemini, now: fixture.now, container: container,
                isCurrent: { true }, save: { _ in throw CocoaError(.fileWriteUnknown) })
        }
        guard case let .ready(.draft(saved)) = try ObservationReanalysisPersistence.preparation(draft.identity,
            container: container, isCurrent: { true }) else { Issue.record("Admission partially committed"); return }
        #expect(saved == draft)
        #expect(try Store.candidates(ownerID: draft.identity.ownerID, container: container, isCurrent: { true }).isEmpty)
    }
    @Test(arguments: ["metadata", "timestamp", "error", "owner", "deletion"])
    func malformedOrForeignPendingNeverCreatesWake(_ damage: String) throws {
        let container = try fixture.fixture.fixture.container(), draft = try stage(container); _ = try admit(draft, container)
        let (context, row, job) = try fixture.fixture.stored(container)
        switch damage {
        case "metadata": job.metadataJSON = "not-json"
        case "timestamp": row.queueUpdatedAt = fixture.now.addingTimeInterval(1)
        case "error": job.lastErrorCode = "future-error"; row.queueLastErrorCode = "future-error"
        case "owner": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        default: context.insert(PendingCloudDeletionTask(scanId: draft.identity.observationID.uuidString.lowercased()))
        }
        try context.save()
        #expect(try Store.candidates(ownerID: draft.identity.ownerID, container: container, isCurrent: { true }).isEmpty)
    }
    @Test(arguments: ["ready", "recovery", "consent", "account", "draft-change"])
    func preflightCannotBindStaleDeniedOrRecoveryOnlyDraft(_ result: String) async throws {
        let container = try fixture.fixture.fixture.container(), draft = try stage(container)
        var current = true, finished = false
        let admission = ObservationReanalysisAdmission(account: ObservationReanalysisProducerTests().account(
            current: { current }, finish: { finished = true }), preflight: { input, owner, validate in
                try validate()
                #expect(input.analysisID == draft.identity.analysisID && owner == draft.identity.ownerID)
                if result == "consent" { throw MerianError.aiConsentRequired }
                if result == "account" { current = false }
                if result == "draft-change" {
                    let (context, _, job) = try fixture.fixture.stored(container)
                    job.metadataJSON = "{}"; try context.save()
                }
                return .init(recipient: result == "recovery" ? .recoveryOnly : .gemini, validate: validate)
            }, now: { fixture.now })
        if result == "ready" {
            let pending = try await admission.admit(draft, container: container, isCurrent: { true })
            #expect(pending.status == .pending && pending.intent.request.processor == .gemini)
        } else {
            await #expect(throws: (any Error).self) { try await admission.admit(draft, container: container, isCurrent: { true }) }
            #expect(try fixture.fixture.stored(container).2.status == .needsAttention)
        }
        #expect(finished)
    }
    @Test func boundReplayUsesSavedConsentAndNeverRediscoversRecipient() async throws {
        let container = try fixture.fixture.fixture.container(); _ = try fixture.fixture.stage(container)
        let draft = try draft(); var authorizations = 0
        let admission = ObservationReanalysisAdmission(account: ObservationReanalysisProducerTests().account(),
            preflight: { _, _, _ in Issue.record("Bound request re-preflighted"); throw MerianError.invalidResponse },
            authorizeBound: { processor, _, validate in
                #expect(processor == .gemini); authorizations += 1
                return .init(recipient: processor, validate: validate)
            }, now: { fixture.now })
        let first = try await admission.admit(draft, container: container, isCurrent: { true })
        #expect(try await admission.admit(draft, container: container, isCurrent: { true }) == first)
        #expect(authorizations == 1)
    }
}
