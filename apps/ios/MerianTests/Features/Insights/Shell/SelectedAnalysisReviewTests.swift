import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct SelectedAnalysisReviewTests {
    let fixture = ObservationAnalysisReviewAdmissionTests()

    func baseline(_ ticket: ObservationAnalysisReviewTicket) throws -> SelectedAnalysisReviewBaseline {
        try #require(.init(scanID: ticket.observationID.uuidString, ownerID: ticket.ownerID.uuidString,
            analysisID: ticket.analysisID.uuidString, revision: ticket.observationRevision))
    }

    func access(current: @escaping () -> Bool = { true }, wake: @escaping () -> Void = {}) -> SelectedAnalysisReviewAccess {
        var cloud = fixture.source.support.client(fetch: { _ in
            Issue.record("Opening selected review must not fetch or dispatch")
            throw ObservationHistoryError.unavailable
        }, current: current)
        cloud.begin = { owner in
            guard owner == fixture.source.support.owner else { throw ObservationHistoryError.accountChanged }
            return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false))
        }
        return .prepared(cloud: cloud, session: { id, container in
            try IdentificationHistorySession(observation: id, container: container, cloud: cloud,
                reviewWake: wake, currentGeneration: { 1 }, sessionIsCurrent: { _ in current() })
        })
    }

    @Test func openingIsReadOnlyAndClosingInvalidatesTheExactTicket() async throws {
        let (container, ticket) = try await fixture.seed()
        var wakes = 0
        let session = try access(wake: { wakes += 1 }).open(baseline(ticket), container)
        #expect(session.ticket == ticket && session.isScopeCurrent())
        #expect(wakes == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        session.close()
        #expect(!session.isScopeCurrent())
    }

    @Test(arguments: ["revision", "selection", "owner", "delete"])
    func staleDisplayedTargetCannotOpenOrRemainCurrent(_ change: String) async throws {
        let (container, ticket) = try await fixture.seed(), shown = try baseline(ticket)
        let adapter = access(), session = try adapter.open(shown, container)
        try fixture.source.update(container) { record, context in
            switch change {
            case "revision": record.observationStateRevision = 11
            case "selection": record.selectedAnalysisID = UUID().uuidString.lowercased()
            case "owner": record.analysisOwnerAccountID = UUID().uuidString.lowercased()
            default: context.delete(record)
            }
        }
        #expect(!session.matchesDisplayedTicket())
        #expect(session.isScopeCurrent() == (change == "revision" || change == "selection"))
        #expect(throws: (any Error).self) { try adapter.open(shown, container) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func contextAdvanceDuringCachedReadRejectsOpening() async throws {
        let (container, ticket) = try await fixture.seed()
        var armed = false, checks = 0
        let cloud = fixture.source.support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: {
            if armed {
                checks += 1
                if checks == 3 {
                    try? fixture.source.update(container) { scan, _ in scan.observationStateRevision = 11 }
                }
            }
            return true
        })
        let adapter = SelectedAnalysisReviewAccess.prepared(cloud: cloud, session: { id, container in
            let session = try IdentificationHistorySession(observation: id, container: container, cloud: cloud,
                reviewWake: {}, currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
            armed = true
            return session
        })
        #expect(throws: (any Error).self) { try adapter.open(baseline(ticket), container) }
        #expect(checks >= 3)
    }

    @Test func accountLossInvalidatesWithoutDispatch() async throws {
        let (container, ticket) = try await fixture.seed()
        var current = true
        let adapter = access(current: { current }), session = try adapter.open(baseline(ticket), container)
        current = false
        #expect(!session.isScopeCurrent())
        #expect(throws: (any Error).self) { try adapter.open(baseline(ticket), container) }
    }

    @Test func metadataRefreshAndCollectionEditDoNotAdoptUnseenAuthority() async throws {
        let (container, ticket) = try await fixture.seed(), context = ModelContext(container)
        let vm = InsightSheetViewModel(), engine = InferenceEngine()
        defer { engine.cancelHistoricHydration() }
        #expect(vm.bindPresentedScan(scanId: ticket.observationID.uuidString.lowercased(), modelContext: context, inferenceEngine: engine))
        let shown = try #require(vm.toolbarRecordSnapshot?.selectedReviewBaseline)
        #expect(shown == (try baseline(ticket)))
        let record = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: context)
        record.observationStateRevision = 11
        record.selectedAnalysisID = UUID().uuidString.lowercased()
        let collection = ScanCollection(name: "Synthetic collection")
        context.insert(collection)
        try context.save()
        #expect(vm.fetchLocalRecord(for: record.id, modelContext: context))
        #expect(vm.toolbarRecordSnapshot?.selectedReviewBaseline == shown)
        vm.toggleScanInCollection(collection, modelContext: context)
        #expect(vm.toolbarRecordSnapshot?.selectedReviewBaseline == shown)
        #expect(throws: (any Error).self) { try access().open(shown, container) }
    }

    @Test func sameIDInitialLoadCapturesOnlySuccessfulProjection() async throws {
        let (container, ticket) = try await fixture.seed(), context = ModelContext(container)
        let record = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: context)
        let vm = InsightSheetViewModel(), engine = InferenceEngine()
        defer { engine.cancelHistoricHydration() }
        engine.load(from: record)
        let previous = engine.scanPresentationGeneration
        #expect(vm.bindPresentedScan(scanId: record.id, modelContext: context, inferenceEngine: engine))
        #expect(engine.scanPresentationGeneration != previous)
        #expect(vm.toolbarRecordSnapshot?.selectedReviewBaseline == (try baseline(ticket)))
        let adopted = engine.scanPresentationGeneration
        #expect(vm.bindPresentedScan(scanId: record.id, modelContext: context, inferenceEngine: engine))
        #expect(engine.scanPresentationGeneration == adopted)
        engine.beginAuthTransitionWriteFence()
        #expect(vm.loadSelectedReviewProjection(record, inferenceEngine: engine) == nil)
    }

    @Test func newTapAfterAuthorityAdvanceDoesNotMintAnOperationOrWake() async throws {
        let (container, ticket) = try await fixture.seed()
        var wakes = 0
        let session = try access(wake: { wakes += 1 }).open(baseline(ticket), container)
        let model = session.reviewModel(presentationIsCurrent: { true })
        #expect(model.canSubmit)
        try fixture.source.update(container) { record, _ in record.observationStateRevision = 11 }
        model.submit(.reject)
        #expect(!model.isClosed && model.request == nil && !model.canSubmit && wakes == 0)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        model.refresh()
        #expect(model.undoOperation == nil && !model.canSubmit)
        session.close()
    }

    @Test func reconciledReceiptSurvivesAuthorityAdvanceAndRefreshesOnlyTheParent() async throws {
        let recovery = ObservationAnalysisReviewReconciliationTests()
        let (container, claim) = try await recovery.seeded()
        let shown = try #require(SelectedAnalysisReviewBaseline(scanID: recovery.observation.uuidString,
            ownerID: recovery.owner.uuidString, analysisID: recovery.target.uuidString, revision: 10))
        let adapter = access(), session = try adapter.open(shown, container)
        let model = session.reviewModel(presentationIsCurrent: { true })
        #expect(model.status?.phase == .reconciling)
        let vm = InsightSheetViewModel(dependencies: .init(authenticationSnapshot: {
            .init(isAuthenticated: true, accountID: recovery.owner.uuidString)
        }))
        let engine = InferenceEngine()
        vm.inferenceEngine = engine
        defer { engine.cancelHistoricHydration() }
        #expect(vm.bindPresentedScan(scanId: recovery.observation.uuidString.lowercased(), modelContext: ModelContext(container), inferenceEngine: engine))
        let generation = vm.scanBoundActionGeneration
        let service = ObservationAnalysisReviewReconciliation(cloud: recovery.cloud(
            targetData: try recovery.targetData(selectedID: recovery.target), selectedData: Data()), now: { recovery.date })
        _ = try await service.reconcile(claim, container: container, isCurrent: { true })
        #expect(session.isScopeCurrent() && !session.matchesDisplayedTicket())
        model.refresh()
        #expect(!model.isClosed && model.status?.phase == .complete(.applied(observationRevision: 11, reviewRevision: 1)) && model.terminalMessage != nil)
        #expect(vm.toolbarRecordSnapshot?.selectedReviewBaseline == shown)
        #expect(throws: (any Error).self) { try session.access.stage(session.ticket.request(.reject, operationID: UUID()), session.ticket) }
        vm.refreshAcknowledgedHistory(scanId: recovery.observation.uuidString.lowercased(), generation: generation,
            container: container, inferenceEngine: engine)
        let refreshed = try #require(vm.toolbarRecordSnapshot?.selectedReviewBaseline)
        #expect(refreshed.revision == 12 && refreshed.analysisID == shown.analysisID)
        let freshSession = try adapter.open(refreshed, container)
        #expect(freshSession.ticket.reviewRevision == 1 && freshSession.matchesDisplayedTicket())
        freshSession.close(); session.close()
    }

    @Test func snapshotNeverInfersAuthorityFromFreshMetadataOrAnotherObservation() async throws {
        let (container, ticket) = try await fixture.seed(), context = ModelContext(container)
        let record = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: context)
        #expect(InsightToolbarRecordSnapshot(record: record).selectedReviewBaseline == nil)
        let other = try #require(SelectedAnalysisReviewBaseline(scanID: UUID().uuidString,
            ownerID: ticket.ownerID.uuidString, analysisID: ticket.analysisID.uuidString, revision: 10))
        #expect(InsightToolbarRecordSnapshot(record: record, selectedReviewBaseline: other).selectedReviewBaseline == nil)
        #expect(SelectedAnalysisReviewBaseline(scanID: record.id, ownerID: nil, analysisID: ticket.analysisID.uuidString, revision: 10) == nil)
        #expect(SelectedAnalysisReviewBaseline(scanID: record.id, ownerID: ticket.ownerID.uuidString, analysisID: ticket.analysisID.uuidString, revision: 0) == nil)
    }
}
