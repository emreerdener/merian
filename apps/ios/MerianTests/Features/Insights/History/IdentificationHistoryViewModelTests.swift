import Foundation
@testable import Merian
import Observation
import Testing
import UIKit

@MainActor @Suite(.serialized)
struct IdentificationHistoryViewModelTests {
    @MainActor final class Fixture {
        let owner = UUID(), a = UUID(), b = UUID()
        var selected: UUID
        var target: UUID?
        var operation: UUID?
        var undo: UUID?
        var revision = 1
        var sends = 0, prepares = 0, reads = 0, admissions = 0
        var current = true, failSend = false, conflict = false
        var now = Date()
        init() { selected = a }
        var context: ObservationHistoryListingService.Context { .init(owner: owner, selected: selected, revision: revision, pendingOperation: operation, undoOperation: undo) }
        func row(_ id: UUID) -> IdentificationHistoryRow { .init(id: id, title: id == a ? "First" : "Second", scientificName: nil, completedAt: nil, confidence: nil, review: "Not confirmed", isImported: true) }
        var dependencies: IdentificationHistoryDependencies {
            .init(context: { self.context }, page: { before in
                self.reads += 1
                return .init(rows: before == nil ? [self.row(self.a), self.row(self.b)] : [self.row(UUID())], nextBeforeOrdinal: before == nil ? 3 : nil, context: self.context)
            }, preview: { id in .init(row: self.row(id), reasoning: nil, alternatives: [], evidenceDescription: nil, photoIDs: [], canRestore: id != self.selected, isCached: false) },
                prepare: { id in self.prepares += 1; self.target = id; self.operation = UUID() },
                prepareUndo: { operation in
                    #expect(operation == self.undo)
                    self.prepares += 1; self.target = self.a; self.operation = UUID()
                }, sendPending: {
                    self.sends += 1
                    if self.failSend { throw ObservationHistoryError.unavailable }
                    let op = try #require(self.operation), target = try #require(self.target), previous = self.selected
                    self.operation = nil; self.target = nil; self.revision += 1
                    if self.conflict {
                        self.undo = nil
                        return .rejected(.init(schema_version: 1, operation_id: op.uuidString.lowercased(), observation_id: self.owner.uuidString.lowercased(), analysis_id: target.uuidString.lowercased(), expected_observation_revision: self.revision-1, expected_review_revision: 0, outcome: "revision_conflict"))
                    }
                    self.selected = target; self.undo = op
                    return .selected(.init(schema_version: 1, operation_id: op.uuidString.lowercased(), observation_id: self.owner.uuidString.lowercased(), previous_analysis_id: previous.uuidString.lowercased(), selected_analysis_id: target.uuidString.lowercased(), observation_revision: self.revision, review_revision: 0))
                }, photo: { _, _ in throw ObservationHistoryError.unavailable }, isCurrent: { self.current }, close: { self.current = false }, now: { self.now })
        }
        func model() -> IdentificationHistoryViewModel { .init(dependencies: dependencies, didAdmit: { self.admissions += 1 }) }
    }
    @Test func completionRefreshesListButKeepsOpenExactPreviewUntilBack() async {
        let fixture = Fixture(), model = fixture.model()
        await model.perform(.newest)
        model.refreshForLibraryChange()
        while fixture.reads < 2 || model.isBusy { await Task.yield() }
        #expect(model.selected == fixture.a && fixture.prepares == 0)
        await Task.yield()
        await model.perform(.preview(fixture.a))
        let reads = fixture.reads
        model.refreshForLibraryChange(); model.refreshForLibraryChange()
        await Task.yield()
        #expect(model.detail?.row.id == fixture.a && fixture.reads == reads)
        model.back()
        while fixture.reads == reads || model.isBusy { await Task.yield() }
        #expect(fixture.reads == reads + 1 && model.detail == nil && model.selected == fixture.a)
        fixture.current = false; model.refreshForLibraryChange()
        #expect(model.isClosed && model.rows.isEmpty)
    }

    @Test func previewIsReadOnlyAndRestoreUndoUseAcknowledgedIdentity() async {
        let fixture = Fixture(), model = fixture.model()
        await model.perform(.newest); await model.perform(.preview(fixture.b))
        #expect(fixture.prepares == 0 && fixture.sends == 0 && model.selected == fixture.a)
        #expect(fixture.admissions == 0)
        await model.perform(.restore)
        #expect(model.selected == fixture.b && model.undoOperation == fixture.undo && !model.pending)
        #expect(fixture.admissions == 1)
        await model.perform(.undo)
        #expect(model.selected == fixture.a && fixture.prepares == 2 && fixture.sends == 2)
        #expect(model.rows.count == 2)
    }
    @Test func lostResponseKeepsPendingAndRetryDoesNotPrepareAnotherOperation() async {
        let fixture = Fixture(), model = fixture.model()
        await model.perform(.newest); await model.perform(.preview(fixture.b)); fixture.failSend = true
        await model.perform(.restore)
        let operation = fixture.operation
        let reads = fixture.reads
        model.refreshForLibraryChange()
        await Task.yield()
        #expect(fixture.reads == reads && fixture.operation == operation)
        #expect(model.pending && model.selected == fixture.a && model.undoOperation == nil)
        await model.perform(.restore)
        #expect(fixture.prepares == 1 && fixture.operation == operation)
        fixture.failSend = false; await model.perform(.retry)
        #expect(!model.pending && model.selected == fixture.b && fixture.prepares == 1 && fixture.sends == 2)
    }
    @Test func conflictRefreshesCurrentStateWithoutRebasingOrUndo() async {
        let fixture = Fixture(), model = fixture.model(); fixture.conflict = true
        await model.perform(.newest); await model.perform(.preview(fixture.b)); await model.perform(.restore)
        #expect(!model.pending && model.selected == fixture.a && model.undoOperation == nil && model.detail == nil)
        #expect(model.message?.contains("changed elsewhere") == true)
        await model.perform(.restore); #expect(fixture.prepares == 1)
    }
    @Test func pageWindowReplacesRowsAndUndoExpiresOrInvalidatesWithRevision() async {
        let fixture = Fixture(), model = fixture.model()
        await model.perform(.newest); await model.perform(.older)
        #expect(model.rows.count == 1 && model.showingOlder && model.nextBeforeOrdinal == nil)
        await model.perform(.newest); await model.perform(.preview(fixture.b)); await model.perform(.restore)
        fixture.now += 16; model.validate(); #expect(model.undoOperation == nil)
        await model.perform(.undo); #expect(fixture.prepares == 1)
    }
    @Test func closeOrAccountChangeDiscardsLatePreviewAndPrivateValues() async {
        for accountChange in [false, true] {
            let fixture = Fixture()
            var dependencies = fixture.dependencies
            var resume: CheckedContinuation<IdentificationHistoryDetail, Never>?
            dependencies.preview = { _ in await withCheckedContinuation { resume = $0 } }
            let model = IdentificationHistoryViewModel(dependencies: dependencies)
            await model.perform(.newest)
            let work = Task { await model.perform(.preview(fixture.b)) }
            while resume == nil { await Task.yield() }
            if accountChange { fixture.current = false } else { model.close() }
            resume?.resume(returning: .init(row: fixture.row(fixture.b), reasoning: "private", alternatives: [], evidenceDescription: nil, photoIDs: [], canRestore: true, isCached: false))
            await work.value
            #expect(model.isClosed && model.rows.isEmpty && model.detail == nil && model.photo == nil)
            #expect(fixture.sends == 0)
        }
    }
    @Test func invalidAndOversizedPagesDoNotReplaceVisibleHistory() async {
        let fixture = Fixture(); var dependencies = fixture.dependencies
        dependencies.page = { _ in .init(rows: Array(repeating: fixture.row(fixture.a), count: 21), nextBeforeOrdinal: nil, context: fixture.context) }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest)
        #expect(model.rows.isEmpty && model.message != nil)
    }
    @Test func newerPhotoRequestWinsEvenWhenEarlierPhotoReturnsLast() async {
        let fixture = Fixture(), first = UUID(), second = UUID()
        var dependencies = fixture.dependencies
        var resume: [UUID: CheckedContinuation<UIImage, Never>] = [:]
        dependencies.preview = { id in .init(row: fixture.row(id), reasoning: nil, alternatives: [], evidenceDescription: nil, photoIDs: [first, second], canRestore: true, isCached: false) }
        dependencies.photo = { _, media in await withCheckedContinuation { resume[media] = $0 } }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest); await model.perform(.preview(fixture.b))
        let older = Task { await model.loadPhoto(first) }
        while resume[first] == nil { await Task.yield() }
        let newer = Task { await model.loadPhoto(second) }
        while resume[second] == nil { await Task.yield() }
        let image = UIImage()
        resume[second]?.resume(returning: image); await newer.value
        resume[first]?.resume(returning: UIImage()); await older.value
        #expect(model.photo === image)
        model.back(); #expect(model.photo == nil)
    }
    @Test func authorityRevisionChangeRefreshesParentOnceWithoutChangingSelection() async {
        let fixture = Fixture(), model = fixture.model()
        await model.perform(.newest); await model.perform(.older)
        #expect(fixture.admissions == 0)
        fixture.revision += 1
        model.validate(); model.validate()
        #expect(fixture.admissions == 1 && model.selected == fixture.a)
        fixture.current = false
        #expect(!model.isSessionCurrent)
        model.validate(); #expect(model.isClosed && model.rows.isEmpty)
    }

    @Test func revisionChangeInvalidatesPreviewAndAuthorityBearingRows() async {
        let fixture = Fixture(), model = fixture.model()
        await model.perform(.newest); await model.perform(.preview(fixture.b))
        #expect(model.detail?.canRestore == true && model.rows.count == 2)
        fixture.revision += 1
        model.validate()
        #expect(model.rows.isEmpty && model.detail == nil && model.photo == nil)
        #expect(model.nextBeforeOrdinal == nil && !model.showingOlder)
        await model.perform(.restore)
        #expect(fixture.prepares == 0 && fixture.admissions == 1)
        await model.perform(.newest)
        #expect(model.rows.count == 2 && fixture.admissions == 1)
    }

    @Test func delayedPageCannotReinstallAnOlderSelectionOrAuthority() async {
        let fixture = Fixture()
        var dependencies = fixture.dependencies
        var resume: CheckedContinuation<IdentificationHistoryPage, Never>?
        var delay = false
        let original = dependencies.page
        dependencies.page = { before in
            if delay { return await withCheckedContinuation { resume = $0 } }
            return try await original(before)
        }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest)
        let stale = IdentificationHistoryPage(rows: [fixture.row(fixture.a)], nextBeforeOrdinal: nil, context: fixture.context)
        delay = true
        let work = Task { await model.perform(.newest) }
        while resume == nil { await Task.yield() }
        fixture.revision += 1; fixture.selected = fixture.b
        resume?.resume(returning: stale); await work.value
        #expect(model.selected == fixture.b && model.rows.isEmpty && model.detail == nil)
    }

    @Test func delayedPreviewCannotOutliveItsAuthorityRevision() async {
        let fixture = Fixture()
        var dependencies = fixture.dependencies
        var resume: CheckedContinuation<IdentificationHistoryDetail, Never>?
        dependencies.preview = { _ in await withCheckedContinuation { resume = $0 } }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest)
        let work = Task { await model.perform(.preview(fixture.b)) }
        while resume == nil { await Task.yield() }
        fixture.revision += 1
        resume?.resume(returning: .init(row: fixture.row(fixture.b), reasoning: nil, alternatives: [], evidenceDescription: nil, photoIDs: [], canRestore: true, isCached: false))
        await work.value
        #expect(model.rows.isEmpty && model.detail == nil)
        await model.perform(.restore); #expect(fixture.prepares == 0)
    }

    @Test func backCannotAbandonAnInFlightSelection() async {
        let fixture = Fixture()
        var dependencies = fixture.dependencies
        var resume: CheckedContinuation<Void, Never>?
        let original = dependencies.sendPending
        dependencies.sendPending = {
            await withCheckedContinuation { resume = $0 }
            return try await original()
        }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest); await model.perform(.preview(fixture.b))
        let work = Task { await model.perform(.restore) }
        while resume == nil { await Task.yield() }
        model.back()
        #expect(model.isBusy && model.detail != nil && model.pending)
        resume?.resume(); await work.value
        #expect(fixture.sends == 1 && model.selected == fixture.b && model.rows.count == 2)
    }

    @Test func failedPostAcknowledgmentRefreshPreservesReceiptAndUndo() async {
        let fixture = Fixture()
        var dependencies = fixture.dependencies
        let original = dependencies.page
        dependencies.page = { before in
            if fixture.revision > 1 { throw ObservationHistoryError.unavailable }
            return try await original(before)
        }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest); await model.perform(.preview(fixture.b)); await model.perform(.restore)
        #expect(model.selected == fixture.b && !model.pending && model.undoOperation == fixture.undo)
        #expect(model.rows.isEmpty && model.detail == nil && fixture.sends == 1)
    }

    @Test func accountTransitionInvalidatesObservedSessionBeforeUserChanges() async {
        let fixture = Fixture(), runtime = AuthRuntimeState()
        var dependencies = fixture.dependencies
        dependencies.isCurrent = { runtime.activeTransition == nil }
        let model = IdentificationHistoryViewModel(dependencies: dependencies)
        await model.perform(.newest); await model.perform(.preview(fixture.b))
        await confirmation("History observes account transition admission") { changed in
            withObservationTracking {
                _ = model.isSessionCurrent
            } onChange: { changed() }
            _ = runtime.beginTransition(kind: .signOut, sourceSession: nil)
        }
        #expect(!model.isSessionCurrent)
        model.validate()
        #expect(model.isClosed && model.rows.isEmpty && model.detail == nil)
    }
}
