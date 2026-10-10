import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureReanalysisEditorTests {
    let fixture = CaptureReanalysisSessionTests()

    @Test func explicitSelectionLoadsMoreThanOrdinaryCapacityAndSubmitsOnlyChosenEvidence() async throws {
        let seed = try fixture.seed(count: 6), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var delivered: [UUID] = []
        let editor = make(seed, root: root, submitted: { child in
            do {
                let context = ModelContext(seed.container)
                let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
                let saved = try ObservationReanalysisSubmissionIntent.decode(Data(try #require(job.metadataJSON).utf8))
                #expect(saved.draft.identity.analysisID == child)
                for path in saved.draft.photoPaths { #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)) }
                delivered.append(child)
            } catch { Issue.record(error) }
        })
        #expect(editor.selectedPhotoIDs.isEmpty && !editor.canSubmit)
        for photo in seed.source.photos.suffix(3) { editor.toggle(photo.mediaID) }
        await editor.loadSelection()
        #expect(editor.phase == .editing && editor.capture.images.count == 3)
        #expect(editor.capture.images.map(\.reanalysisProvenance) == seed.source.photos.suffix(3).map {
            .original(analysisID: seed.source.analysisID, photo: $0)
        })
        editor.removeNote(at: 0)
        editor.setNote("Edited synthetic note", at: 0)
        await editor.submit()
        #expect(editor.phase == .submitted && editor.isFrozen && !editor.canEdit)
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let intent = try ObservationReanalysisSubmissionIntent.decode(Data(try #require(job.metadataJSON).utf8))
        let draft = intent.draft
        #expect(delivered == [draft.identity.analysisID])
        #expect(draft.evidence.count == 8 && row.work == .reanalysis(draft.identity))
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
        #expect(job.attemptCount == 0 && job.status == .needsAttention)
    }

    @Test func failedStageRetainsIdentityAndSuccessfulDiscardRetiresIt() async throws {
        let seed = try fixture.seed(), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var calls = 0, cleanup = 0, deliveries = 0
        let account = fixture.fixture.account()
        let producer = ObservationReanalysisProducer(files: .init(documents: root), ownership: .init(), account: account, loadOriginal: { _, _, _ in
            calls += 1; throw MerianError.invalidResponse
        })
        let editor = make(seed, root: root, producer: producer, cleanup: { cleanup += 1 }, submitted: { _ in deliveries += 1 })
        editor.toggle(seed.source.photos[0].mediaID); await editor.loadSelection()
        await editor.submit()
        #expect(editor.phase == .editing && editor.isFrozen && !editor.canEdit && editor.canSubmit)
        await editor.submit()
        #expect(calls == 2 && deliveries == 0)
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
        #expect(editor.errorMessage == nil && !editor.canSubmit && !editor.discard())
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func accountTeardownDoesNotInventDurableCancellation() async throws {
        let seed = try fixture.seed(), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var cleanup = 0
        let editor = make(seed, root: root, cleanup: { cleanup += 1 })
        editor.toggle(seed.source.photos[0].mediaID); await editor.loadSelection(); await editor.submit()
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
        let access = CaptureReanalysisAccess.prepared(ownership: .init(), account: fixture.fixture.account(), isCurrentOwner: { UUID() }, generation: { 1 }, requestSubmitted: { _ in }, requestCleanup: {})
        #expect(throws: ObservationHistoryError.accountChanged) { try access.open(target, seed.container) }
    }

    @Test func failedFileWriteRetriesTheSamePersistedSubmissionBeforeWaking() async throws {
        let seed = try fixture.seed(count: 1), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let obstruction = root.appendingPathComponent("ReanalysisQueue")
        try Data([1]).write(to: obstruction)
        var delivered: [UUID] = []
        let editor = make(seed, root: root, submitted: { delivered.append($0) })
        editor.toggle(seed.source.photos[0].mediaID); await editor.loadSelection(); await editor.submit()
        #expect(editor.phase == .editing && editor.isFrozen && delivered.isEmpty)
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let pending = try ObservationReanalysisPreparationIntent.decode(Data(try #require(job.metadataJSON).utf8))
        #expect(pending.action == .submit)
        try FileManager.default.removeItem(at: obstruction)
        await editor.submit()
        let updated = ModelContext(seed.container)
        let ready = try #require(updated.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let submitted = try ObservationReanalysisSubmissionIntent.decode(Data(try #require(ready.metadataJSON).utf8))
        #expect(submitted.preparation == pending && delivered == [pending.draft.identity.analysisID])
        #expect(editor.phase == .submitted)
    }

    @Test(arguments: [false, true])
    func staleCompletionWithholdsWakeAndBoundReplayDoesNotReenterAdmission(bound: Bool) async throws {
        let seed = try fixture.seed(count: 1), root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var withholdReady = true, delivered: [UUID] = []
        let editor = make(seed, root: root, submitted: { delivered.append($0) }, current: {
            guard withholdReady else { return true }
            guard let text = try? ModelContext(seed.container).fetch(FetchDescriptor<OfflineJobRecord>()).first?.metadataJSON else { return true }
            return (try? ObservationReanalysisSubmissionIntent.decode(Data(text.utf8))) == nil
        })
        editor.toggle(seed.source.photos[0].mediaID); await editor.loadSelection(); await editor.submit()
        #expect(editor.phase == .editing && delivered.isEmpty)
        let job = try #require(ModelContext(seed.container).fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let saved = try ObservationReanalysisSubmissionIntent.decode(Data(try #require(job.metadataJSON).utf8))
        if bound {
            _ = try ObservationReanalysisExecutionStore.bindAndAdmit(saved.draft, processor: .gemini, now: Date(),
                container: seed.container, isCurrent: { true }, submissionProof: saved.preparation.verified(source: seed.source))
        }
        withholdReady = false
        await editor.submit()
        #expect(editor.phase == .submitted)
        #expect(delivered == (bound ? [] : [saved.draft.identity.analysisID]))
    }

    @Test func importedBaselineContinuesEmptyAndSubmitsOnlyExplicitNewEvidence() async throws {
        let original = try fixture.fixture.fixture.seed(version: 3), bytes = try fixture.fixture.image()
        let source = try fixture.fixture.source(original)
        let seed = CaptureReanalysisSessionTests.Seed(container: original.container, source: source, bytes: bytes)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var delivered: [UUID] = []
        let account = fixture.fixture.account()
        let loader = CaptureReanalysisEvidenceLoader(account: account, loadPhoto: { _, _, _ in
            Issue.record("An imported baseline must not load mutable parent photos"); throw MerianError.invalidResponse
        })
        let producer = ObservationReanalysisProducer(files: .init(documents: root), ownership: .init(), account: account,
            loadOriginal: { _, _, _ in
                Issue.record("New evidence must not borrow an original photo"); throw MerianError.invalidResponse
            })
        let editor = make(seed, root: root, loader: loader, producer: producer, submitted: { delivered.append($0) })
        #expect(editor.photos.isEmpty && editor.selectedPhotoIDs.isEmpty)
        await editor.loadSelection()
        #expect(editor.phase == .editing && editor.canEdit && editor.capture.isEmpty && !editor.canSubmit)
        await editor.submit()
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        let image = try #require(UIImage(data: bytes)?.cgImage)
        editor.addPhoto(.init(compressedData: bytes, displayData: bytes, historicalContext: nil,
            previewCGImage: SendableCGImage(image: image)))
        #expect(editor.capture.images.count == 1 && editor.capture.images[0].reanalysisProvenance == .added)
        #expect(editor.capture.observationContexts.isEmpty && editor.canSubmit)
        await editor.submit()
        #expect(editor.phase == .submitted)
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let intent = try ObservationReanalysisSubmissionIntent.decode(Data(try #require(job.metadataJSON).utf8))
        #expect(intent.draft.identity.sourceAnalysisID == source.analysisID)
        #expect(intent.draft.evidence.count == 1 && intent.draft.photoPaths.count == 1)
        #expect(delivered == [intent.draft.identity.analysisID])
        #expect(try context.fetch(FetchDescriptor<LocalScanRecord>()).first?.selectedAnalysisID == source.analysisID.uuidString.lowercased())
    }

    private func make(_ seed: CaptureReanalysisSessionTests.Seed, root: URL,
                      loader: CaptureReanalysisEvidenceLoader? = nil, producer: ObservationReanalysisProducer? = nil,
                      cleanup: @escaping @MainActor () -> Void = {},
                      submitted: @escaping @MainActor (UUID) -> Void = { _ in },
                      current: @escaping @MainActor () -> Bool = { true }) -> CaptureReanalysisEditor {
        let account = fixture.fixture.account()
        return CaptureReanalysisEditor(source: seed.source, container: seed.container, account: account,
            loader: loader ?? .init(account: account, loadPhoto: { _, _, _ in seed.bytes }),
            producer: producer ?? .init(files: .init(documents: root), ownership: .init(), account: account, loadOriginal: { _, _, _ in seed.bytes }),
            isCurrent: current, requestSubmitted: submitted, requestCleanup: cleanup)
    }
}
