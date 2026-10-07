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
