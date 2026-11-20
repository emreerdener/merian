import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct CaptureAudioSourceSavedModelTests {
    typealias Row = ObservationAudioSourceSavedStatus.Summary
    func row(_ phase: ObservationAudioSourceSavedStatus.Phase = .unknown) -> Row {
        .init(identity: .init(observationID: UUID(), sourceAnalysisID: UUID(), analysisID: UUID(), ownerID: UUID()), phase: phase)
    }
    func idle(_ model: CaptureAudioSourceSavedRequestsModel) async {
        while model.isBusy { await Task.yield() }
    }

    @Test func onlyExplicitSelectionAndFinalTapOpenExactOriginalBeforeTask() async {
        let first = row(), second = row(.reserved)
        var opens: [OfflineQueueWork.Reanalysis] = [], resumes = 0
        let model = CaptureAudioSourceSavedRequestsModel(status: .init(isCurrent: { true }, page: { _, limit, _ in
            #expect(limit == 20); return .init(items: [first, second], next: nil, omittedCount: 0)
        }), openResume: { identity in
            opens.append(identity)
            return .init(resume: { current in #expect(current()); resumes += 1; return .unavailable })
        }, isPresented: { true })
        model.start(); await idle(model)
        #expect(model.selected == nil && opens.isEmpty && resumes == 0)
        model.continueSelected(); model.select(row()); model.continueSelected()
        #expect(opens.isEmpty)
        model.select(second); model.continueSelected()
        #expect(opens == [second.identity] && resumes == 0)
        await idle(model)
        #expect(resumes == 1 && model.selected == second.identity && model.message != nil)
        model.continueSelected(); await idle(model)
        #expect(opens == [second.identity, second.identity] && resumes == 2)
    }

    @Test func failedRefreshClearsRowsSelectionAndCannotInventAbsenceOrActions() async {
        let saved = row()
        var fail = false, opens = 0
        let model = CaptureAudioSourceSavedRequestsModel(status: .init(isCurrent: { true }, page: { _, _, _ in
            if fail { throw MerianError.invalidResponse }
            return .init(items: [saved], next: nil, omittedCount: 2)
        }), openResume: { _ in opens += 1; throw MerianError.invalidResponse }, isPresented: { true })
        model.start(); await idle(model); model.select(saved)
        fail = true; model.start()
        #expect(model.rows.isEmpty && model.selected == nil && model.omittedCount == 0)
        await idle(model); model.continueSelected()
        #expect(model.message != nil && model.rows.isEmpty && opens == 0 && model.next == nil)
        model.close(); model.start(); model.select(saved); model.continueSelected()
        #expect(model.isClosed && opens == 0)
    }

    @Test(arguments: ["close", "account", "presentation"])
    func latePageCannotRestorePrivateState(_ change: String) async {
        let saved = row()
        var current = true, presented = true, continuation: CheckedContinuation<ObservationAudioSourceSavedStatus.Page, Never>?
        let model = CaptureAudioSourceSavedRequestsModel(status: .init(isCurrent: { current }, page: { _, _, _ in
            await withCheckedContinuation { continuation = $0 }
        }), openResume: { _ in Issue.record("Reading dispatched"); throw MerianError.invalidResponse }, isPresented: { presented })
        model.start(); while continuation == nil { await Task.yield() }
        if change == "close" { model.close() } else if change == "account" { current = false } else { presented = false }
        continuation?.resume(returning: .init(items: [saved], next: nil, omittedCount: 0))
        await idle(model); await Task.yield()
        #expect(model.rows.isEmpty && model.selected == nil)
    }

    @Test func lateResumeCannotReopenClosedPresentation() async {
        let saved = row()
        var continuation: CheckedContinuation<Void, Never>?, settled = false
        let model = CaptureAudioSourceSavedRequestsModel(status: .init(isCurrent: { true }, page: { _, _, _ in
            .init(items: [saved], next: nil, omittedCount: 0)
        }), openResume: { _ in .init(resume: { _ in
            await withCheckedContinuation { continuation = $0 }
            settled = true
            return .started
        }) }, isPresented: { true })
        model.start(); await idle(model); model.select(saved); model.continueSelected()
        while continuation == nil { await Task.yield() }
        model.close(); continuation?.resume()
        while !settled { await Task.yield() }
        #expect(model.isClosed && model.rows.isEmpty && model.message == nil)
    }
    @Test func realPagesReplaceAndForwardOpaqueCursorWithoutAutomaticSelection() async throws {
        let fixture = ObservationAudioPreparationTests(), seed = try await ObservationAudioExecutionStoreTests().ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try ObservationAudioSourceSubmissionTests().state("staged", seed: seed)
        let context = ModelContext(seed.container)
        for index in 1...20 {
            let child = try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 100)))
            try ObservationReanalysisPersistence.insert(.init(observationID: seed.source.observationID,
                sourceAnalysisID: seed.source.analysisID, analysisID: child, ownerID: seed.source.ownerID),
                paths: [], metadata: Data("{}".utf8), context: context)
        }
        try context.save()
        let access = CaptureAudioSourceStatusAccess.prepared(account: fixture.fixture.account(), owner: .init(), reader: .init(),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true }, containerIsCurrent: { _ in true })
        let model = CaptureAudioSourceSavedRequestsModel(status: try access.open(seed.source.ownerID, seed.source.observationID, seed.container),
            openResume: { _ in Issue.record("Paging resumed work"); throw MerianError.invalidResponse }, isPresented: { true })
        model.start(); await idle(model)
        #expect(model.rows.isEmpty && model.omittedCount == 20 && model.next != nil)
        model.start(more: true); await idle(model)
        #expect(model.rows.map(\.identity) == [seed.preparation.identity] && model.next == nil && model.selected == nil)
        model.select(try #require(model.rows.first)); model.start(); await idle(model)
        #expect(model.selected == nil && model.rows.isEmpty && model.next != nil)
    }

    @Test func inertFactoryContinuesExactUnknownSourceWithoutFilesOrExecutionFallback() async throws {
        let fixture = ObservationAudioSourceSubmissionTests(), seed = try await fixture.fixture.fixture.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let original = try fixture.state("unknown", seed: seed)
        try FileManager.default.removeItem(at: seed.file)
        var starts = 0
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: ObservationReanalysisProducerTests().account(),
            currentOwner: { seed.source.ownerID }, generation: { 1 }, sessionIsCurrent: { _ in true }, preparationOwner: .init(),
            enrollmentOwner: .init(), containerIsCurrent: { $0 === seed.container }, submitted: { _ in Issue.record("Photo admission") }, cleanup: {},
            audioStatusOwner: .init(), audioSource: .init(start: { _, _, _, _ in Issue.record("Source used execution fallback"); return .unavailable },
                sourceStart: { key, _, _, _ in starts += 1; #expect(key.snapshot == original); return .unavailable }), documents: { seed.root })
        let model = try bundle.openSavedAudioSources(ownerID: seed.source.ownerID, observationID: seed.source.observationID,
            container: seed.container, isPresented: { true })
        model.start(); await idle(model)
        #expect(starts == 0 && model.selected == nil)
        let saved = try #require(model.rows.first)
        #expect(saved.phase == .unknown)
        model.select(saved); model.continueSelected(); await idle(model)
        #expect(starts == 1 && model.selected == seed.preparation.identity)
    }
}
