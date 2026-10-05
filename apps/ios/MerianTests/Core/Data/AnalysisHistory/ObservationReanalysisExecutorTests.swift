import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisExecutorTests {
    typealias Executor = ObservationReanalysisExecutor
    typealias Store = ObservationReanalysisExecutionStore
    let fixture = ObservationReanalysisExecutionTests()

    @MainActor final class Calls {
        var phases: [String] = []
        var current = true
        var finished = 0
        var complete: Data?
        var after: (String) throws -> Void = { _ in }
        var state = ObservationAnalysisReceipt.State.complete
    }
    func executor(_ calls: Calls) -> Executor {
        let dependencies = Executor.Dependencies(recover: { _, validate in
            try validate(); calls.phases.append("recover"); try calls.after("recover")
            return calls.complete
        }, authorize: { intent, validate in
            try validate(); calls.phases.append("authorize"); try calls.after("authorize")
            return IdentificationDispatchAuthorization(recipient: intent.request.processor, validate: validate)
        }, read: { draft, validate in
            try validate(); calls.phases.append("read"); try calls.after("read")
            let references = draft.evidence.compactMap { item -> ObservationEvidenceUpload.Reference? in
                if case let .image(photo) = item { return photo }; return nil
            }
            return references.map { .init(mediaID: $0.mediaID, contentType: $0.contentType, bytes: Data([1, 2, 3])) }
        }, upload: { upload, _, validate in
            try validate(); calls.phases.append("upload"); try calls.after("upload")
            let prepared = try upload.prepare()
            return .init(observationID: prepared.observationID, analysisID: prepared.analysisID, items: prepared.references)
        }, analyze: { intent, authorization in
            try authorization.validate(); calls.phases.append("analyze"); try calls.after("analyze")
            return .init(observationID: intent.request.observationID, analysisID: intent.request.analysisID, state: calls.state)
        })
        return Executor(dependencies: dependencies, account: ObservationReanalysisProducerTests().account(
            current: { calls.current }, finish: { calls.finished += 1 }), now: { fixture.now })
    }
    func stage(_ container: ModelContainer) throws -> Store.Snapshot {
        _ = try fixture.fixture.stage(container)
        return try Store.read(fixture.fixture.intent().identity, container: container, isCurrent: { true })
    }
    func snapshot(_ container: ModelContainer) throws -> Store.Snapshot {
        try Store.read(fixture.fixture.intent().identity, container: container, isCurrent: { true })
    }
    @Test func completedRecoveryPrecedesConsentAndMissingEvidenceAndPreservesSelection() async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.complete = try fixture.result()
        let outcome = try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        guard case .completed = outcome else { Issue.record("Expected completion"); return }
        #expect(calls.phases == ["recover"] && calls.finished == 1)
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == fixture.fixture.fixture.analysis.uuidString.lowercased())
        #expect(parent.observationStateRevision == 3 && parent.analysisRecords?.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(saved.intent.request.analysisID)) != nil)
    }
    @Test func exactNewAttemptRecoversAuthoritativeBytesAfterCompletionReceipt() async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls(), bytes = try fixture.result()
        calls.after = { phase in if phase == "analyze" { calls.complete = bytes } }
        let outcome = try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        guard case .completed = outcome else { Issue.record("Expected completion"); return }
        #expect(calls.phases == ["recover", "authorize", "read", "upload", "analyze", "recover"])
        #expect(calls.finished == 1)
    }
    @Test(arguments: ObservationAnalysisReceipt.State.allCases)
    func receiptAloneNeverInventsAResult(_ state: ObservationAnalysisReceipt.State) async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.state = state
        _ = try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        let after = try snapshot(container)
        #expect(after.intent == saved.intent && after.attempt == 1)
        #expect(after.status == (state == .failedTerminal ? .needsAttention : .waiting))
        #expect(after.server == state)
        #expect(after.hold == (state == .failedTerminal ? .terminalFailure : nil))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
    }
    @Test(arguments: ["recover", "authorize", "read", "upload", "analyze"])
    func accountChangeAfterAnyAwaitWithholdsAllFurtherWork(_ phase: String) async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.after = { completed in if completed == phase { calls.current = false } }
        await #expect(throws: (any Error).self) {
            try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        }
        #expect(calls.phases.last == phase && calls.finished == 1)
        #expect(try snapshot(container).status == .running)
    }
    @Test(arguments: ["recover", "upload", "analyze"])
    func uncertainResponseWaitsAndNextAttemptRecoversBeforeResending(_ phase: String) async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.after = { completed in if completed == phase { throw URLError(.networkConnectionLost) } }
        _ = try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        let waiting = try snapshot(container)
        #expect(waiting.status == .waiting && waiting.intent == saved.intent)
        calls.phases = []; calls.after = { _ in }; calls.complete = try fixture.result()
        var next = executor(calls); next.now = { waiting.nextRun! }
        _ = try await next.execute(waiting, admission: .dueRetry, container: container, isCurrent: { true })
        #expect(calls.phases == ["recover"])
    }
    @Test(arguments: ["evidence", "consent", "conflict", "unavailable", "files", "cancel", "invalid-page"])
    func exactFailuresHoldOrWaitWithoutLosingEvidence(_ kind: String) async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.after = { _ in
            switch kind {
            case "consent": throw MerianError.aiConsentRequired
            case "files": throw ObservationReanalysisFileStore.Failure.incomplete
            case "cancel": throw CancellationError()
            case "invalid-page": throw ObservationHistoryError.invalidPage
            default:
                let code = kind == "evidence" ? "analysis_history_evidence_unavailable" :
                    (kind == "conflict" ? "analysis_history_operation_conflict" : "analysis_history_unavailable")
                throw MerianError.httpError(statusCode: 503, message: "{\"code\":\"\(code)\"}")
            }
        }
        if kind == "cancel" {
            await #expect(throws: CancellationError.self) {
                try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
            }
        } else {
            _ = try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        }
        let after = try snapshot(container)
        #expect(after.intent == saved.intent && calls.finished == 1)
        #expect(calls.phases == ["recover"])
        let hold: Store.Hold? = switch kind {
        case "evidence", "files": .evidenceUnavailable
        case "consent": .consentRequired
        case "conflict", "invalid-page": .reconciliationRequired
        default: nil
        }
        #expect(after.hold == hold)
        #expect(after.status == (kind == "cancel" ? .running : (hold == nil ? .waiting : .needsAttention)))
    }
    @Test func newerClaimCannotBeOverwrittenByAnOldResponse() async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.after = { _ in
            let running = try snapshot(container)
            _ = try Store.claim(running, admission: .interrupted, now: fixture.now, container: container, isCurrent: { true })
        }
        await #expect(throws: (any Error).self) {
            try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        }
        #expect(calls.phases == ["recover"])
        #expect(try snapshot(container).attempt == 2)
    }
    @Test func changedFileCohortCannotReachUploadOrAnalyze() async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        var worker = executor(calls)
        worker.dependencies.read = { _, validate in
            try validate(); calls.phases.append("read")
            return [.init(mediaID: fixture.fixture.media, contentType: "image/jpeg", bytes: Data([3, 2, 1]))]
        }
        _ = try await worker.execute(saved, admission: .initial, container: container, isCurrent: { true })
        #expect(calls.phases == ["recover", "authorize", "read"])
        #expect(try snapshot(container).hold == .reconciliationRequired)
    }
    @Test func deletionDuringRecoveryCannotAppendOrDispatch() async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.complete = try fixture.result()
        calls.after = { _ in
            let context = ModelContext(container)
            context.insert(PendingCloudDeletionTask(scanId: saved.intent.request.observationID.uuidString.lowercased()))
            try context.save()
        }
        await #expect(throws: (any Error).self) {
            try await executor(calls).execute(saved, admission: .initial, container: container, isCurrent: { true })
        }
        #expect(calls.phases == ["recover"] && calls.finished == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
    }
    @Test func retryBudgetHoldsSameIdentityWithoutProviderSuccessor() async throws {
        let container = try fixture.fixture.fixture.container(), saved = try stage(container), calls = Calls()
        calls.after = { _ in throw URLError(.timedOut) }
        var worker = executor(calls), next = saved, admission = Store.Admission.initial
        for _ in 0..<OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts {
            let date = next.nextRun ?? fixture.now; worker.now = { date }
            _ = try await worker.execute(next, admission: admission, container: container, isCurrent: { true })
            next = try snapshot(container); admission = .dueRetry
        }
        #expect(next.intent == saved.intent && next.hold == .retryLimit && next.nextRun == nil)
        #expect(calls.phases.allSatisfy { $0 == "recover" })
    }
}
