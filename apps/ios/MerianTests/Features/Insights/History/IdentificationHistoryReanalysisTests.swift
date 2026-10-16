import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct IdentificationHistoryReanalysisTests {
    let fixture = ObservationReanalysisProducerTests()

    @Test func preparedRouteAdapterIsExplicitAndUsesOnlyHistoricalIdentity() throws {
        let routes = AppRouteCoordinator()
        let target = HistoricalReanalysisTarget(observationID: UUID(), analysisID: UUID(), ownerID: UUID())
        #expect(IdentificationHistoryAccess.prepared.requestReanalysis == nil)
        let access = IdentificationHistoryAccess.prepared(routes: routes)
        #expect(routes.pendingRequests.isEmpty)
        let request = try #require(access.requestReanalysis)
        request(target)
        let envelope = try #require(routes.pendingRequests.first)
        guard case let .historicalReanalysis(saved) = envelope.route else { Issue.record("Wrong route"); return }
        #expect(saved == target && envelope.source == .internalUserAction)
        routes.beginAccountSession(accountID: UUID().uuidString, origin: .runtimeTransition)
        #expect(routes.pendingRequests.isEmpty && routes.claimNext() == nil)
    }

    @Test func historicalSourceRoutesAfterDismissalWithoutSelectingOrAdmitting() async throws {
        let seed = try fixture.fixture.seed(), owner = fixture.fixture.fixture.owner
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let selected = UUID(); parent.selectedAnalysisID = selected.uuidString.lowercased(); try context.save()
        let cloud = fixture.account()
        let session = try IdentificationHistorySession(observation: seed.observationID.uuidString, container: seed.container,
            cloud: cloud, currentGeneration: { 1 }, sessionIsCurrent: { $0.userID == owner })
        let baseline = try session.dependencies.context()
        let action = try session.reanalysisAction(seed.result.analysisID, context: baseline)
        var targets: [HistoricalReanalysisTarget] = []
        let handoff = IdentificationHistoryReanalysisHandoff(scanID: parent.id, generation: 7, action: action, dispatch: { targets.append($0) })
        #expect(targets.isEmpty)
        session.close() // Exact nested dismissal closes idle private presentation first.
        try handoff.resume { id, generation in id == parent.id && generation == 7 }
        #expect(targets == [.init(observationID: seed.observationID, analysisID: seed.result.analysisID, ownerID: owner)])
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(parent.selectedAnalysisID == selected.uuidString.lowercased())
    }

    @Test(arguments: ["account", "generation", "revision", "deleted-source", "changed-source", "deleted-parent"])
    func delayedHandoffRejectsChangedAuthorityOrSource(reason: String) throws {
        let seed = try fixture.fixture.seed(), cloud = fixture.account()
        var generation: UInt64 = 1, current = true
        let session = try IdentificationHistorySession(observation: seed.observationID.uuidString, container: seed.container,
            cloud: cloud, currentGeneration: { generation }, sessionIsCurrent: { _ in current })
        let action = try session.reanalysisAction(seed.result.analysisID, context: session.dependencies.context())
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let source = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        switch reason {
        case "account": current = false
        case "generation": generation += 1
        case "revision": parent.observationStateRevision = try #require(parent.observationStateRevision) + 1
        case "deleted-source": context.delete(source)
        case "changed-source":
            let object = try JSONSerialization.jsonObject(with: source.resultSnapshotData)
            let replacement = try LocalAnalysisRecord(analysisID: seed.result.analysisID, observationID: parent.id,
                ownerAccountID: fixture.fixture.fixture.owner, completedAt: source.completedAt, snapshotVersion: source.snapshotVersion,
                resultSnapshotData: JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]))
            context.delete(source); try context.save()
            context.insert(replacement); parent.analysisRecords = [replacement]
        default: context.delete(parent)
        }
        try context.save()
        session.close()
        var dispatched = false
        let handoff = IdentificationHistoryReanalysisHandoff(scanID: parent.id, generation: 1, action: action, dispatch: { _ in dispatched = true })
        #expect(throws: (any Error).self) { try handoff.resume { _, _ in true } }
        #expect(!dispatched)
    }

    @Test func missingSourceAndPendingSelectionCannotProduceCapability() throws {
        let seed = try fixture.fixture.seed(), session = try IdentificationHistorySession(
            observation: seed.observationID.uuidString, container: seed.container, cloud: fixture.account(),
            currentGeneration: { 1 }, sessionIsCurrent: { _ in true })
        let baseline = try session.dependencies.context()
        #expect(throws: (any Error).self) { try session.reanalysisAction(UUID(), context: baseline) }
        let pending = ObservationHistoryListingService.Context(owner: baseline.owner, selected: baseline.selected,
            revision: baseline.revision, pendingOperation: UUID(), undoOperation: nil)
        #expect(throws: (any Error).self) { try session.reanalysisAction(seed.result.analysisID, context: pending) }
    }

    @Test func previewRequiresExplicitHandoffAndRevalidatesBeforeStaging() async throws {
        let fixture = IdentificationHistoryViewModelTests.Fixture(), observation = UUID()
        var dependencies = fixture.dependencies, resolves = 0, dispatched = 0
        dependencies.reanalysis = { analysis, baseline in
            .init(resolve: {
                resolves += 1
                guard fixture.context == baseline else { throw ObservationHistoryPreviewService.AdmissionError.refreshRequired }
                return .init(observationID: observation, analysisID: analysis, ownerID: fixture.owner)
            })
        }
        let readOnly = IdentificationHistoryViewModel(dependencies: dependencies)
        await readOnly.perform(.newest); await readOnly.perform(.preview(fixture.b))
        #expect(!readOnly.canReanalyze)
        var pending: IdentificationHistoryReanalysisAction?
        let model = IdentificationHistoryViewModel(dependencies: dependencies, handoffReanalysis: { pending = $0; return true })
        await model.perform(.newest); await model.perform(.preview(fixture.b))
        #expect(model.canReanalyze)
        await model.perform(.reanalyze)
        #expect(pending != nil && resolves == 1 && fixture.prepares == 0 && fixture.sends == 0)
        let handoff = IdentificationHistoryReanalysisHandoff(scanID: observation.uuidString, generation: 1,
            action: try #require(pending), dispatch: { _ in dispatched += 1 })
        try handoff.resume { _, _ in false }
        #expect(dispatched == 0 && resolves == 1)
        fixture.revision += 1
        #expect(throws: (any Error).self) { try handoff.resume { _, _ in true } }
        #expect(dispatched == 0)
        await model.perform(.reanalyze)
        #expect(model.detail == nil && !model.canReanalyze)
    }
}
