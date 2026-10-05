import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureReanalysisEditorTests {
    let fixture = CaptureReanalysisSessionTests()

    @Test func explicitSelectionLoadsMoreThanOrdinaryCapacityAndSavesOnlyChosenEvidence() async throws {
        let seed = try fixture.seed(count: 6), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let editor = make(seed, root: root)
        #expect(editor.selectedPhotoIDs.isEmpty && !editor.canSave)
        for photo in seed.source.photos.suffix(3) { editor.toggle(photo.mediaID) }
        await editor.loadSelection()
        #expect(editor.phase == .editing && editor.capture.images.count == 3)
        #expect(editor.capture.images.map(\.reanalysisProvenance) == seed.source.photos.suffix(3).map {
            .original(analysisID: seed.source.analysisID, photo: $0)
        })
        editor.removeNote(at: 0)
        editor.setNote("Edited synthetic note", at: 0)
        await editor.save()
        #expect(editor.phase == .saved && editor.isFrozen && !editor.canEdit)
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let draft = try ObservationReanalysisDraft.decode(Data(try #require(job.metadataJSON).utf8))
        #expect(draft.evidence.count == 8 && row.work == .reanalysis(draft.identity))
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
        #expect(job.attemptCount == 0 && job.status == .needsAttention)
    }

    @Test func failedStageRetainsIdentityAndSuccessfulDiscardRetiresIt() async throws {
        let seed = try fixture.seed(), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var calls = 0, cleanup = 0
        let account = fixture.fixture.account()
        let producer = ObservationReanalysisProducer(files: .init(documents: root), ownership: .init(), account: account, loadOriginal: { _, _, _ in
            calls += 1; throw MerianError.invalidResponse
        })
        let editor = make(seed, root: root, producer: producer, cleanup: { cleanup += 1 })
        editor.toggle(seed.source.photos[0].mediaID); await editor.loadSelection()
        await editor.save()
        #expect(editor.phase == .editing && editor.isFrozen && !editor.canEdit && editor.canSave)
        await editor.save()
        #expect(calls == 2)
        #expect(editor.discard() && cleanup == 1 && editor.phase == .closed)
        let context = ModelContext(seed.container)
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(jobs.count == 1 && jobs[0].kind == .observationReanalysisErasure)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(editor.photos.isEmpty && editor.capture.isEmpty)
    }

    @Test func invalidationDuringSuspendedLoadWithholdsOldOwnerMedia() async throws {
        let seed = try fixture.seed(), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var invalidate: () -> Void = {}
        let loader = CaptureReanalysisEvidenceLoader(account: fixture.fixture.account(), loadPhoto: { _, _, _ in
            invalidate(); return seed.bytes
        })
        let editor = make(seed, root: root, loader: loader)
        invalidate = { editor.invalidate() }
        editor.toggle(seed.source.photos[0].mediaID); await editor.loadSelection()
        #expect(editor.phase == .closed && editor.photos.isEmpty && editor.capture.isEmpty)
        #expect(editor.errorMessage == nil && !editor.canSave && !editor.discard())
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func accountTeardownDoesNotInventDurableCancellation() async throws {
        let seed = try fixture.seed(), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var cleanup = 0
        let editor = make(seed, root: root, cleanup: { cleanup += 1 })
        editor.toggle(seed.source.photos[0].mediaID); await editor.loadSelection(); await editor.save()
        let workspace = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
        workspace.reanalysisEditor = editor; workspace.activeSheet = .reanalysis
        workspace.handleRouteAccountGenerationChanged()
        #expect(workspace.activeSheet == nil && workspace.reanalysisEditor == nil)
        let context = ModelContext(seed.container)
        #expect(cleanup == 0 && editor.capture.isEmpty && editor.photos.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try context.fetch(FetchDescriptor<OfflineJobRecord>()).allSatisfy { $0.kind == .observationReanalysisSync })
    }

    @Test func routeIdentityIncludesOwnerAndHistoricalTargetAndAccessRejectsWrongOwner() throws {
        let seed = try fixture.seed()
        let target = HistoricalReanalysisTarget(observationID: seed.source.observationID, analysisID: seed.source.analysisID, ownerID: seed.source.ownerID)
        let route = AppRoute.historicalReanalysis(target)
        #expect(route.isAccountSensitive && route.coalesces(with: route))
        #expect(!route.coalesces(with: .historicalReanalysis(.init(observationID: target.observationID, analysisID: UUID(), ownerID: target.ownerID))))
        #expect(!route.coalesces(with: .historicalReanalysis(.init(observationID: target.observationID, analysisID: target.analysisID, ownerID: UUID()))))
        let access = CaptureReanalysisAccess.prepared(ownership: .init(), account: fixture.fixture.account(), isCurrentOwner: { UUID() }, generation: { 1 }, requestCleanup: {})
        #expect(throws: ObservationHistoryError.accountChanged) { try access.open(target, seed.container) }
    }

    private func make(_ seed: CaptureReanalysisSessionTests.Seed, root: URL,
                      loader: CaptureReanalysisEvidenceLoader? = nil, producer: ObservationReanalysisProducer? = nil,
                      cleanup: @escaping @MainActor () -> Void = {}) -> CaptureReanalysisEditor {
        let account = fixture.fixture.account()
        return CaptureReanalysisEditor(source: seed.source, container: seed.container, account: account,
            loader: loader ?? .init(account: account, loadPhoto: { _, _, _ in seed.bytes }),
            producer: producer ?? .init(files: .init(documents: root), ownership: .init(), account: account, loadOriginal: { _, _, _ in seed.bytes }),
            isCurrent: { true }, requestCleanup: cleanup)
    }
}
