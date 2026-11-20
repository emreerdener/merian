import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ReanalysisOperationStatusTests {
    typealias Reader = ObservationReanalysisOperationStatus
    let preparation = ObservationReanalysisRecoveryTests()
    let execution = ObservationReanalysisExecutionTests()
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func reader() -> Reader { .init(account: preparation.producerFixture.account()) }
    func page(_ identity: OfflineQueueWork.Reanalysis, _ container: ModelContainer) throws -> Reader.Page {
        try reader().page(observationID: identity.observationID, ownerID: identity.ownerID, container: container, isCurrent: { true })
    }

    @Test func submittedPreparationAndVerifiedReadyStateAreReadableWithoutConsentOrMutation() async throws {
        let seed = try preparation.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let identity = seed.pending.draft.identity
        let original = try ObservationReanalysisAdmissionStore.read(identity, container: seed.container, isCurrent: { true })
        #expect(try page(identity, seed.container).items == [.init(id: identity.analysisID, sourceAnalysisID: identity.sourceAnalysisID, phase: .preparingEvidence)])
        #expect(try ObservationReanalysisAdmissionStore.read(identity, container: seed.container, isCurrent: { true }) == original)
        try await preparation.publish(seed); _ = try await preparation.recover(seed)
        #expect(try page(identity, seed.container).items.first?.phase == .waitingToStart)
        let context = ModelContext(seed.container), parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == identity.sourceAnalysisID.uuidString.lowercased() && parent.observationStateRevision == 10)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: [ObservationReanalysisAdmissionWork.Hold.consentRequired, .evidenceUnavailable, .reconciliationRequired, .retryLimit])
    func advisoryHoldsRemainDistinctAndInert(_ hold: ObservationReanalysisAdmissionWork.Hold) throws {
        let seed = try preparation.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let identity = seed.pending.draft.identity
        let snapshot = try ObservationReanalysisAdmissionStore.read(identity, container: seed.container, isCurrent: { true })
        let claim = try ObservationReanalysisAdmissionStore.claim(snapshot, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        try ObservationReanalysisAdmissionStore.settle(claim, as: .held(hold), now: now, container: seed.container, isCurrent: { true })
        let held = try ObservationReanalysisAdmissionStore.read(identity, container: seed.container, isCurrent: { true })
        let expected: Reader.Phase
        switch hold {
        case .consentRequired: expected = .consentRequired
        case .evidenceUnavailable: expected = .evidenceUnavailable
        case .reconciliationRequired: expected = .reconciliationRequired
        case .retryLimit: expected = .retryLimit
        }
        #expect(try page(identity, seed.container).items.first?.phase == expected)
        #expect(try ObservationReanalysisAdmissionStore.read(identity, container: seed.container, isCurrent: { true }) == held)
    }

    @Test func delayedAdvisoryRetryIsNotPresentedAsReady() throws {
        let seed = try preparation.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let identity = seed.pending.draft.identity
        let snapshot = try ObservationReanalysisAdmissionStore.read(identity, container: seed.container, isCurrent: { true })
        let claim = try ObservationReanalysisAdmissionStore.claim(snapshot, admission: .initial, now: now, container: seed.container, isCurrent: { true })
        try ObservationReanalysisAdmissionStore.settle(claim, as: .waiting(now.addingTimeInterval(30)), now: now, container: seed.container, isCurrent: { true })
        #expect(try page(identity, seed.container).items.first?.phase == .waitingToRetry)
    }

    @Test(arguments: [ObservationReanalysisExecutionStore.Hold.consentRequired, .evidenceUnavailable, .terminalFailure, .reconciliationRequired, .retryLimit])
    func boundHoldsPreserveSavedRequestAndAttempt(_ hold: ObservationReanalysisExecutionStore.Hold) throws {
        let container = try execution.fixture.fixture.container(), claim = try execution.claim(container)
        try ObservationReanalysisExecutionStore.settle(claim, as: .held(hold), now: execution.now, container: container, isCurrent: { true })
        let before = try ObservationReanalysisExecutionStore.read(claim.intent.identity, container: container, isCurrent: { true })
        let expected: Reader.Phase
        switch hold {
        case .consentRequired: expected = .consentRequired
        case .evidenceUnavailable: expected = .evidenceUnavailable
        case .terminalFailure: expected = .terminalFailure
        case .reconciliationRequired: expected = .reconciliationRequired
        case .retryLimit: expected = .retryLimit
        }
        #expect(try page(claim.intent.identity, container).items.first?.phase == expected)
        #expect(try ObservationReanalysisExecutionStore.read(claim.intent.identity, container: container, isCurrent: { true }) == before)
    }

    @Test func runningWaitingAndCompletedResultsDoNotInventRemoteProgress() throws {
        let container = try execution.fixture.fixture.container(), initial = try execution.claim(container)
        let claim = try ObservationReanalysisExecutionStore.consumeDispatch(initial, container: container, isCurrent: { true })
        let identity = claim.intent.identity
        #expect(try page(identity, container).items.first?.phase == .processing)
        try ObservationReanalysisExecutionStore.settle(claim, as: .waiting(until: execution.now.addingTimeInterval(30), server: .dispatched),
            now: execution.now, container: container, isCurrent: { true })
        #expect(try page(identity, container).items.first?.phase == .waitingToRetry)
        let waiting = try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: { true })
        let next = try ObservationReanalysisExecutionStore.claim(waiting, admission: .dueRetry, now: execution.now.addingTimeInterval(30),
            container: container, isCurrent: { true })
        _ = try ObservationReanalysisExecutionStore.complete(next, resultBytes: execution.result(), container: container, isCurrent: { true })
        #expect(try page(identity, container).items.isEmpty)
    }

    @Test func boundedPaginationAdvancesOverCorruptionAndFiltersOtherOwnersAndParents() throws {
        let seed = try preparation.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        // Remove the random first linkage, then use a deterministic ordered cohort.
        _ = try ObservationReanalysisPersistence.discardPreparation(source: seed.source, analysisID: seed.pending.draft.identity.analysisID,
            container: seed.container, isCurrent: { true })
        var children: [UUID] = []
        // Numeric-aware localized sorting puts 2a before 10000000, unlike the cursor predicate.
        for prefix in ["10000000", "2a000000", "30b00000", "40000000", "50000000"] {
            let child = try #require(UUID(uuidString: "\(prefix)-0000-4000-8000-000000000001")); children.append(child)
            let draft = try ObservationReanalysisDraft(identity: .init(observationID: seed.source.observationID, sourceAnalysisID: seed.source.analysisID,
                analysisID: child, ownerID: seed.source.ownerID), evidence: seed.pending.draft.evidence)
            let intent = try ObservationReanalysisPreparationIntent(draft: draft, source: seed.source, action: .submit)
            _ = try ObservationReanalysisPersistence.beginPreparation(intent.verified(source: seed.source), container: seed.container, isCurrent: { true })
        }
        let context = ModelContext(seed.container), rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>(sortBy: [SortDescriptor(\.id, comparator: .lexical)]))
        let savedJob = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: rows[0].id))
        let job = try #require(savedJob)
        job.metadataJSON = "{}"
        rows[3].reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        rows[4].parentObservationID = UUID().uuidString.lowercased(); try context.save()
        let first = try reader().page(observationID: seed.source.observationID, ownerID: seed.source.ownerID, limit: 1,
            container: seed.container, isCurrent: { true })
        #expect(first.items.isEmpty && first.next != nil)
        let second = try reader().page(observationID: seed.source.observationID, ownerID: seed.source.ownerID, after: first.next, limit: 1,
            container: seed.container, isCurrent: { true })
        #expect(second.items.map(\.id) == [children[1]] && second.next != nil)
        let last = try reader().page(observationID: seed.source.observationID, ownerID: seed.source.ownerID, after: second.next, limit: 1,
            container: seed.container, isCurrent: { true })
        #expect(last.items.map(\.id) == [children[2]] && last.next == nil)
    }

    @Test(arguments: ["draft", "metadata", "child-deletion", "missing-job", "receipt"])
    func unsubmittedCorruptOrDeletedChildrenAreNotPresentedAsLiveWork(_ damage: String) throws {
        let seed = try preparation.seed(action: damage == "draft" ? .hold : .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let context = ModelContext(seed.container), job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        switch damage {
        case "metadata": job.metadataJSON = "{}"
        case "child-deletion": context.insert(PendingCloudDeletionTask(scanId: seed.pending.draft.identity.analysisID.uuidString))
        case "missing-job": context.delete(job)
        case "receipt":
            try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.pending.draft.identity.analysisID).record(in: context)
        default: break
        }
        try context.save()
        #expect(try page(seed.pending.draft.identity, seed.container).items.isEmpty)
    }

    @Test func statusIsRecoveredFromDiskWithoutAProducerOrRuntime() throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("status.sqlite")
        let identity: OfflineQueueWork.Reanalysis
        do {
            let seed = try preparation.seed(action: .submit, url: url)
            defer { try? FileManager.default.removeItem(at: seed.root) }
            identity = seed.pending.draft.identity
            #expect(try page(identity, seed.container).items.first?.phase == .preparingEvidence)
        }
        let reopened = try preparation.sourceFixture.fixture.container(url: url, seed: false)
        #expect(try page(identity, reopened).items == [.init(id: identity.analysisID, sourceAnalysisID: identity.sourceAnalysisID, phase: .preparingEvidence)])
    }

    @Test(arguments: ["owner", "parent-deletion", "caller", "lease", "late-lease", "limit"])
    func privateScopeAndFinalLeaseValidationFailClosed(_ reason: String) throws {
        let seed = try preparation.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        var checks = 0, finishes = 0
        let account = preparation.producerFixture.account(current: {
            checks += 1; return reason != "lease" && (reason != "late-lease" || checks < 3)
        }, finish: { finishes += 1 })
        if reason == "parent-deletion" {
            let context = ModelContext(seed.container)
            context.insert(PendingCloudDeletionTask(scanId: seed.source.observationID.uuidString)); try context.save()
        }
        #expect(throws: (any Error).self) {
            try Reader(account: account).page(observationID: seed.source.observationID, ownerID: reason == "owner" ? UUID() : seed.source.ownerID,
                limit: reason == "limit" ? 21 : 20, container: seed.container, isCurrent: { reason != "caller" })
        }
        #expect(finishes == (reason == "limit" ? 0 : 1))
    }
}

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ReanalysisRetirementActionTests {
    typealias Store = ObservationReanalysisExecutionStore
    typealias Action = ObservationReanalysisRetirementAction
    let fixture = ReanalysisRetirementStagingTests()
    enum Failure: Error { case saved }

    @Test(arguments: ["admitted", "absent", "dispatched", "draft", "complete", "failed_terminal"])
    func onlyExactAdmittedStatusCanStage(_ state: String) async throws {
        let container = try fixture.execution.fixture.fixture.container(), claim = try fixture.consumed(container)
        var reads = 0, wakes = 0, finishes = 0
        let action = Action(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(finish: { finishes += 1 }),
            fetch: { request, owner, validate in
                try validate(); reads += 1
                #expect(request == ObservationAnalysisExecutionLookup(claim.intent.request) && owner == claim.intent.ownerID)
                return try fixture.status(claim.intent, state: state)
            }, wake: { wakes += 1 }, now: { fixture.execution.now })
        let result = try await action.perform(claim.intent.identity, operationID: fixture.operation, container: container, isCurrent: { true })
        let saved = try Store.read(claim.intent.identity, container: container, isCurrent: { true })
        #expect(reads == 1 && finishes == 1)
        if state == "admitted" {
            #expect(result == .saved && saved.retirement == fixture.operation && wakes == 1)
            #expect(try ReanalysisOperationStatusTests().page(claim.intent.identity, container).items.first?.phase == .stopping)
        } else {
            #expect(result == .unavailable && saved == claim.snapshot && wakes == 0)
        }
    }

    @Test func committedSaveFailureWakesAndReopeningRetainsOriginalOperation() async throws {
        let container = try fixture.execution.fixture.fixture.container(), claim = try fixture.consumed(container)
        var reads = 0, wakes = 0
        let action = Action(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(),
            fetch: { _, _, validate in try validate(); reads += 1; return try fixture.status(claim.intent) },
            wake: { wakes += 1 }, now: { fixture.execution.now }, save: { try $0.save(); throw Failure.saved })
        await #expect(throws: Failure.self) {
            try await action.perform(claim.intent.identity, operationID: fixture.operation, container: container, isCurrent: { true })
        }
        #expect(wakes == 1)
        let recovered = try await action.perform(claim.intent.identity, operationID: UUID(), container: container, isCurrent: { true })
        let saved = try Store.read(claim.intent.identity, container: container, isCurrent: { true })
        #expect(recovered == .saved && saved.retirement == fixture.operation && reads == 1 && wakes == 2)
    }

    @Test func explicitHeldRetirementRecoveryPreservesRequestWithoutStatusRead() async throws {
        let container = try fixture.execution.fixture.fixture.container()
        let claim = try ReanalysisRetirementSettlementTests().claim(container)
        try Store.holdRetirement(claim, now: fixture.execution.now, container: container, isCurrent: { true })
        let held = try Store.read(claim.snapshot.intent.identity, container: container, isCurrent: { true })
        #expect(Action.affordance(held) == .checkSameStop)
        #expect(try ReanalysisOperationStatusTests().page(held.intent.identity, container).items.first?.phase == .stopNeedsChecking)
        var reads = 0, wakes = 0
        let action = Action(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(),
            fetch: { _, _, _ in reads += 1; throw Failure.saved }, wake: { wakes += 1 }, now: { fixture.execution.now })
        #expect(try await action.perform(held.intent.identity, operationID: UUID(), container: container, isCurrent: { true }) == .saved)
        let saved = try Store.read(held.intent.identity, container: container, isCurrent: { true })
        #expect(saved.retirement == held.retirement && saved.intent == held.intent && saved.dispatch == held.dispatch)
        #expect(saved.status == .waiting && saved.attempt == held.attempt && reads == 0 && wakes == 1)
        #expect(throws: (any Error).self) {
            try Store.rearmRetirement(held, now: fixture.execution.now, container: container, isCurrent: { true })
        }
    }

    @Test(arguments: ["ready", "held", "account", "replaced"])
    func unavailableOrChangedWorkNeverStages(_ reason: String) async throws {
        let container = try fixture.execution.fixture.fixture.container(), initial = try fixture.execution.claim(container)
        let claim = reason == "ready" ? initial : try Store.consumeDispatch(initial, container: container, isCurrent: { true })
        if reason == "held" { try Store.settle(claim, as: .held(.reconciliationRequired), now: fixture.execution.now, container: container, isCurrent: { true }) }
        var current = true, reads = 0, wakes = 0
        let action = Action(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(),
            fetch: { _, _, _ in
                reads += 1
                if reason == "account" { current = false }
                if reason == "replaced" {
                    try Store.settle(claim, as: .held(.retryLimit), now: fixture.execution.now, container: container, isCurrent: { true })
                }
                return try fixture.status(claim.intent)
            }, wake: { wakes += 1 }, now: { fixture.execution.now })
        do {
            let result = try await action.perform(claim.intent.identity, operationID: fixture.operation, container: container, isCurrent: { current })
            #expect((reason == "ready" || reason == "held") && result == .unavailable)
        } catch { #expect(reason == "account" || reason == "replaced") }
        let saved = try Store.read(claim.intent.identity, container: container, isCurrent: { true })
        #expect(saved.retirement == nil && wakes == 0 && reads == ((reason == "ready" || reason == "held") ? 0 : 1))
    }
    @Test func saveFailureBeforeCommitOnlyWakesDiscoveryAndRetainsOriginalRequest() async throws {
        let container = try fixture.execution.fixture.fixture.container(), claim = try fixture.consumed(container)
        var wakes = 0
        let action = Action(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(),
            fetch: { _, _, validate in try validate(); return try fixture.status(claim.intent) },
            wake: { wakes += 1 }, now: { fixture.execution.now }, save: { _ in throw Failure.saved })
        await #expect(throws: Failure.self) {
            try await action.perform(claim.intent.identity, operationID: fixture.operation, container: container, isCurrent: { true })
        }
        #expect(try Store.read(claim.intent.identity, container: container, isCurrent: { true }) == claim.snapshot)
        #expect(wakes == 1)
    }

    @Test func authDrainRetainsLookupUntilLeaseReleaseAndPreventsStaging() async throws {
        let container = try fixture.execution.fixture.fixture.container(), claim = try fixture.consumed(container)
        let ownership = ObservationReanalysisPreparationOwner()
        var reply: CheckedContinuation<ObservationAnalysisExecutionStatus, Never>?
        var finished = 0, wakes = 0, draining = false, drained = false
        let action = Action(ownership: ownership, account: ReanalysisOperationStatusTests().preparation.producerFixture.account(finish: { finished += 1 }),
            fetch: { _, _, _ in await withCheckedContinuation { reply = $0 } }, wake: { wakes += 1 })
        let task = Task { try await action.perform(claim.intent.identity, operationID: fixture.operation, container: container, isCurrent: { true }) }
        while reply == nil { await Task.yield() }
        let drain = Task { draining = true; await ownership.cancelAndAwaitAll(); drained = true }
        while !draining { await Task.yield() }
        #expect(!drained && finished == 0 && ownership.contains(claim.intent.request.analysisID))
        reply?.resume(returning: try fixture.status(claim.intent))
        do { _ = try await task.value; Issue.record("Cancelled lookup must not stage") } catch {}
        await drain.value
        #expect(drained && finished == 1 && wakes == 0 && !ownership.contains(claim.intent.request.analysisID))
        #expect(try Store.read(claim.intent.identity, container: container, isCurrent: { true }) == claim.snapshot)
    }

}

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ReanalysisHeldOutcomeTests {
    typealias Store = ObservationReanalysisExecutionStore
    let execution = ObservationReanalysisExecutionTests()
    enum Failure: Error { case synthetic }

    func held(_ container: ModelContainer, ready: Bool = false) throws -> Store.Snapshot {
        let active = try execution.claim(container)
        let claim = ready ? active : try Store.consumeDispatch(active, container: container, isCurrent: { true })
        try Store.settle(claim, as: .held(.retryLimit), now: execution.now, container: container, isCurrent: { true })
        return try Store.read(claim.intent.identity, container: container, isCurrent: { true })
    }

    @Test(arguments: ["absent", "error", "ready", "malformed"])
    func unknownOrUnsupportedLookupNeverChangesHeldWork(_ mode: String) async throws {
        let container = try execution.fixture.fixture.container(), saved = try held(container, ready: mode == "ready")
        var reads = 0, notifications = 0, finishes = 0
        let action = ObservationReanalysisOutcomeAction(ownership: .init(),
            account: ReanalysisOperationStatusTests().preparation.producerFixture.account(finish: { finishes += 1 }),
            recover: { intent, validate in
                try validate(); reads += 1; #expect(intent == saved.intent)
                if mode == "error" { throw Failure.synthetic }
                return mode == "malformed" ? Data("{}".utf8) : nil
            }, completionAttempted: { notifications += 1 })
        do {
            let result = try await action.perform(saved.intent.identity, container: container, isCurrent: { true })
            #expect(!result && (mode == "absent" || mode == "ready"))
        } catch { #expect(mode == "error" || mode == "malformed") }
        #expect(reads == (mode == "ready" ? 0 : 1) && finishes == 1)
        #expect(notifications == (mode == "malformed" ? 1 : 0))
        #expect(try Store.read(saved.intent.identity, container: container, isCurrent: { true }) == saved)
        #expect(try Store.candidates(ownerID: saved.intent.ownerID, container: container, isCurrent: { true }).isEmpty)
        let row = try #require(ReanalysisOperationStatusTests().page(saved.intent.identity, container).items.first)
        #expect(row.phase == (mode == "ready" ? .retryLimit : .executionRetryLimit) && row.canCheckOutcome == (mode != "ready"))
    }

    @Test(arguments: ["success", "save-before", "save-after"])
    func exactOutcomeCompletesAtomicallyWithoutChangingSelectionOrOriginalRequest(_ mode: String) async throws {
        let container = try execution.fixture.fixture.container(), saved = try held(container)
        var notifications = 0
        let action = ObservationReanalysisOutcomeAction(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(),
            recover: { intent, validate in try validate(); #expect(intent == saved.intent); return try execution.result() },
            completionAttempted: { notifications += 1 }, save: { context in
                if mode == "save-before" { throw Failure.synthetic }
                try context.save()
                if mode == "save-after" { throw Failure.synthetic }
            })
        do {
            let result = try await action.perform(saved.intent.identity, container: container, isCurrent: { true })
            #expect(result && mode == "success")
        } catch { #expect(mode != "success") }
        let context = ModelContext(container), parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == execution.fixture.fixture.analysis.uuidString.lowercased() && notifications == 1)
        if mode == "save-before" {
            #expect(try Store.read(saved.intent.identity, container: container, isCurrent: { true }) == saved)
            #expect(parent.analysisRecords?.count == 1)
        } else {
            #expect(parent.analysisRecords?.count == 2)
            #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
            // Exact completion replay needs neither a fresh claim nor a new operation.
            let receipt = try Store.completeHeldOutcome(saved, resultBytes: execution.result(), container: container, isCurrent: { true })
            #expect(receipt.childID == saved.intent.request.analysisID)
            #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
        }
    }

    @Test(arguments: ["account", "deletion", "changed"])
    func lateOutcomeCannotCrossItsOriginalScope(_ mode: String) async throws {
        let container = try execution.fixture.fixture.container(), saved = try held(container)
        var current = true, notifications = 0
        let action = ObservationReanalysisOutcomeAction(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(),
            recover: { _, validate in
                try validate()
                if mode == "account" { current = false } else {
                    let (context, row, job) = try execution.fixture.stored(container)
                    if mode == "deletion" { context.insert(PendingCloudDeletionTask(scanId: saved.intent.identity.observationID.uuidString.lowercased())) } else { row.queueUpdatedAt = execution.now.addingTimeInterval(1); job.updatedAt = row.queueUpdatedAt }
                    try context.save()
                }
                return try execution.result()
            }, completionAttempted: { notifications += 1 })
        await #expect(throws: (any Error).self) {
            try await action.perform(saved.intent.identity, container: container, isCurrent: { current })
        }
        #expect(notifications == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
    }

    @Test func authDrainRetainsReadUntilLeaseExitAndLeavesHeldWorkUnchanged() async throws {
        let container = try execution.fixture.fixture.container(), saved = try held(container), owner = ObservationReanalysisPreparationOwner()
        var reply: CheckedContinuation<Data?, Never>?
        var finished = 0, drained = false, draining = false, notifications = 0
        let action = ObservationReanalysisOutcomeAction(ownership: owner,
            account: ReanalysisOperationStatusTests().preparation.producerFixture.account(finish: { finished += 1 }),
            recover: { _, _ in await withCheckedContinuation { reply = $0 } }, completionAttempted: { notifications += 1 })
        let task = Task { try await action.perform(saved.intent.identity, container: container, isCurrent: { true }) }
        while reply == nil { await Task.yield() }
        let drain = Task { draining = true; await owner.cancelAndAwaitAll(); drained = true }
        while !draining { await Task.yield() }
        #expect(!drained && finished == 0 && owner.contains(saved.intent.request.analysisID))
        reply?.resume(returning: try execution.result())
        do { _ = try await task.value; Issue.record("Cancelled lookup must not append") } catch {}
        await drain.value
        #expect(drained && finished == 1 && notifications == 0)
        #expect(try Store.read(saved.intent.identity, container: container, isCurrent: { true }) == saved)
    }
    @Test func legacyUnknownHeldWorkRecoversOnlyItsExactResult() async throws {
        let container = try execution.fixture.fixture.container(), before = try held(container)
        let (context, _, job) = try execution.fixture.stored(container)
        job.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: ["version": 1,
            "owner_id": before.intent.ownerID.uuidString.lowercased(), "request_base64": before.intent.request.body.base64EncodedString()]), encoding: .utf8)
        try context.save()
        let saved = try Store.read(before.intent.identity, container: container, isCurrent: { true })
        #expect(saved.dispatch == .legacyUnknown && Store.canRecoverHeldOutcome(saved))
        let action = ObservationReanalysisOutcomeAction(ownership: .init(), account: ReanalysisOperationStatusTests().preparation.producerFixture.account(),
            recover: { intent, validate in try validate(); #expect(intent == before.intent); return try execution.result() }, completionAttempted: {})
        #expect(try await action.perform(saved.intent.identity, container: container, isCurrent: { true }))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
    }

    @Test func restartRetainsHeldRequestAndExactCompletionReceipt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.sqlite")
        let saved: Store.Snapshot
        do { let container = try execution.fixture.fixture.container(url: url); saved = try held(container) }
        do {
            let container = try execution.fixture.fixture.container(url: url, seed: false)
            #expect(try Store.read(saved.intent.identity, container: container, isCurrent: { true }) == saved)
            #expect(try Store.candidates(ownerID: saved.intent.ownerID, container: container, isCurrent: { true }).isEmpty)
            _ = try Store.completeHeldOutcome(saved, resultBytes: execution.result(), container: container, isCurrent: { true })
        }
        let reopened = try execution.fixture.fixture.container(url: url, seed: false)
        _ = try Store.completeHeldOutcome(saved, resultBytes: execution.result(), container: reopened, isCurrent: { true })
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
    }

}
