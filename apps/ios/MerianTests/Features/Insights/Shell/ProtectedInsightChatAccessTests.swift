import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ProtectedInsightChatAccessTests {
    let support = ProtectedInsightChatPersistenceTests()

    func baseline(_ ticket: ProtectedInsightChatTicket) throws -> SelectedAnalysisReviewBaseline {
        try #require(.init(scanID: ticket.observationID.uuidString, ownerID: ticket.ownerID.uuidString,
            analysisID: ticket.selection.analysisID.uuidString, revision: ticket.selection.stateRevision))
    }
    func access(current: @escaping () -> Bool = { true }) -> ProtectedInsightChatAccess {
        var cloud = support.source.support.client(fetch: { _ in
            Issue.record("Opening chat cannot fetch or send"); throw ObservationHistoryError.unavailable
        }, current: current)
        cloud.begin = { owner in .init(id: UUID(), session: .init(userID: owner, isAnonymous: false)) }
        return .prepared(cloud: cloud, session: { id, container in
            try IdentificationHistorySession(observation: id, container: container, cloud: cloud,
                currentGeneration: { 1 }, sessionIsCurrent: { _ in current() })
        })
    }

    @Test func exactDisplayedTicketIsReadOnlyAndCloseInvalidates() async throws {
        let (container, ticket) = try await support.seed(), session = try access().open(baseline(ticket), container)
        #expect(session.ticket == ticket && session.matchesDisplayedTicket())
        #expect(try session.status(nil).completed.isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        session.close()
        #expect(!session.isCurrent() && !session.matchesDisplayedTicket())
        #expect(throws: (any Error).self) { try session.status(nil) }
    }

    @Test(arguments: ["revision", "selection", "owner", "delete"])
    func freshCacheCannotRebaseVisibleBaseline(_ change: String) async throws {
        let (container, ticket) = try await support.seed(), shown = try baseline(ticket)
        let adapter = access(), session = try adapter.open(shown, container)
        try support.source.update(container) { scan, context in
            switch change {
            case "revision": scan.observationStateRevision = 11
            case "selection": scan.selectedAnalysisID = UUID().uuidString.lowercased()
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            default: context.delete(scan)
            }
        }
        #expect(!session.matchesDisplayedTicket())
        #expect(throws: (any Error).self) { try adapter.open(shown, container) }
        #expect(session.ticket == ticket)
    }

    @Test func contextAdvanceDuringCachedReadRejectsOpening() async throws {
        let (container, ticket) = try await support.seed()
        var armed = false, checks = 0
        let cloud = support.source.support.client(fetch: { _ in throw ObservationHistoryError.unavailable }, current: {
            if armed {
                checks += 1
                if checks == 3 { try? support.source.update(container) { scan, _ in scan.observationStateRevision = 11 } }
            }
            return true
        })
        let adapter = ProtectedInsightChatAccess.prepared(cloud: cloud, session: { id, container in
            let scope = try IdentificationHistorySession(observation: id, container: container, cloud: cloud,
                currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
            armed = true
            return scope
        })
        #expect(throws: (any Error).self) { try adapter.open(baseline(ticket), container) }
        #expect(checks >= 3)
    }

    @Test func chatRevisionBoundaryAndAccountLossFailClosed() async throws {
        let (container, ticket) = try await support.seed()
        var current = true
        let adapter = access(current: { current }), session = try adapter.open(baseline(ticket), container)
        current = false
        #expect(!session.isCurrent())
        #expect(throws: (any Error).self) { try session.status(nil) }
        current = true
        try support.source.update(container) { scan, context in
            scan.observationStateRevision = 2_147_483_647
            for state in try context.fetch(FetchDescriptor<LocalAnalysisStateRecord>()) {
                try state.update(observationStateRevision: 2_147_483_647, reviewRevision: state.reviewRevision,
                    reviewSnapshotData: state.reviewSnapshotData, displaySnapshotData: state.displaySnapshotData)
            }
        }
        let max = try #require(SelectedAnalysisReviewBaseline(scanID: ticket.observationID.uuidString,
            ownerID: ticket.ownerID.uuidString, analysisID: ticket.selection.analysisID.uuidString, revision: 2_147_483_647))
        #expect(throws: (any Error).self) { try adapter.open(max, container) }
    }
    @Test(arguments: [false, true])
    func refreshValidatesBothOriginalAndReturnedTicketWithoutMutatingSession(staleBefore: Bool) async throws {
        let (container, ticket) = try await support.seed(), owner = ProtectedInsightChatRefreshOwner()
        var calls = 0
        let cloud = ProtectedInsightChatRefreshOwnerTests().cloud { _ in calls += 1; return try support.source.fixture(revision: 11) }
        let adapter = ProtectedInsightChatAccess.prepared(cloud: cloud,
            configuration: .init(deliver: { _, _, _ in false }, generation: { 0 }, refreshOwner: owner), session: { id, container in
                try IdentificationHistorySession(observation: id, container: container, cloud: cloud,
                    currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
            })
        let session = try adapter.open(baseline(ticket), container), refresh = try #require(session.refreshIdentification)
        if staleBefore {
            _ = try await support.source.service(data: support.source.fixture(revision: 11))
                .syncSelected(observationID: ticket.observationID.uuidString, container: container)
            await #expect(throws: (any Error).self) { try await refresh() }
            #expect(calls == 0)
        } else {
            let fresh = try await refresh()
            #expect(fresh.selection.stateRevision == 11 && calls == 1)
            try session.validateRefreshed(fresh)
            try support.source.update(container) { scan, _ in scan.observationStateRevision = 12 }
            #expect(throws: (any Error).self) { try session.validateRefreshed(fresh) }
        }
        #expect(session.ticket == ticket && !session.matchesDisplayedTicket())
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func displayedProjectionRequiresReturnedAuthorityAndOriginalPresentation() async throws {
        let (container, ticket) = try await support.seed(), shown = try baseline(ticket)
        let vm = InsightSheetViewModel(dependencies: .init(authenticationSnapshot: {
            .init(isAuthenticated: true, accountID: ticket.ownerID.uuidString)
        }))
        let engine = InferenceEngine(); vm.inferenceEngine = engine
        defer { engine.cancelHistoricHydration() }
        #expect(vm.bindPresentedScan(scanId: ticket.observationID.uuidString, modelContext: ModelContext(container), inferenceEngine: engine))
        let generation = vm.scanBoundActionGeneration, engineGeneration = engine.scanPresentationGeneration
        _ = try await support.source.service(data: support.source.fixture(revision: 11))
            .syncSelected(observationID: ticket.observationID.uuidString, container: container)
        #expect(vm.refreshAcknowledgedHistory(scanId: ticket.observationID.uuidString, generation: generation,
            container: container, inferenceEngine: engine, expected: shown) == nil)
        #expect(engine.scanPresentationGeneration == engineGeneration && vm.toolbarRecordSnapshot?.selectedReviewBaseline == shown)
        let fresh = try #require(SelectedAnalysisReviewBaseline(scanID: ticket.observationID.uuidString,
            ownerID: ticket.ownerID.uuidString, analysisID: ticket.selection.analysisID.uuidString, revision: 11))
        #expect(vm.refreshAcknowledgedHistory(scanId: ticket.observationID.uuidString, generation: generation + 1,
            container: container, inferenceEngine: engine, expected: fresh) == nil)
        #expect(vm.refreshAcknowledgedHistory(scanId: ticket.observationID.uuidString, generation: generation,
            container: container, inferenceEngine: engine, expected: fresh) == fresh)
        #expect(vm.toolbarRecordSnapshot?.selectedReviewBaseline == fresh && engine.scanPresentationGeneration != engineGeneration)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

}
