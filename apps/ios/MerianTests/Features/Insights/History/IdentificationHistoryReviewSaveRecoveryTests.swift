import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct HistoryReviewSaveRecoveryTests {
    @Test(arguments: [false, true])
    func committedThrowReopeningDiscoversSameOperation(offline: Bool) async throws {
        let support = ObservationAnalysisReviewAdmissionTests()
        let (container, ticket) = try await support.seed()
        var wakes = 0, online = !offline
        var availableDiscoveries: [UUID] = []
        let pending = {
            try ObservationAnalysisReviewStatus.pending(ownerID: ticket.ownerID, observationID: ticket.observationID,
                container: container, isCurrent: { true })
        }
        let access = IdentificationHistoryReviewAccess(stage: { request, displayed in
            _ = try ObservationAnalysisReviewAdmission.stage(request, ticket: displayed, container: container, isCurrent: { true },
                save: { context in try context.save(); throw ObservationHistoryError.unavailable })
        }, status: { displayed, operation in
            try ObservationAnalysisReviewStatus.read(operationID: operation, ownerID: displayed.ownerID,
                observationID: displayed.observationID, analysisID: displayed.analysisID, container: container, isCurrent: { true })
        }, pending: pending, undo: { _ in nil }, wake: {
            wakes += 1
            if online, let operation = try? pending()?.operationID { availableDiscoveries.append(operation) }
        }, generation: { 0 })
        let first = IdentificationHistoryReviewModel(ticket: ticket, access: access, isCurrent: { true })
        first.submit(.reject)
        let operation = try #require(first.request?.operationID)
        #expect(try pending()?.operationID == operation && wakes == 1)
        first.close()
        online = true
        let reopened = IdentificationHistoryReviewModel(ticket: ticket, access: access, isCurrent: { true })
        reopened.open(); reopened.open(); reopened.refresh()
        #expect(reopened.status?.operationID == operation && !reopened.canSubmit && wakes == 2)
        #expect(availableDiscoveries.last == operation)
        reopened.submit(.reject)
        let jobs = try ModelContext(container).fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(jobs.count == 1)
        // Fresh-context startup discovery retains exactly the persisted identity.
        let stored = try #require(jobs.first)
        #expect(try ObservationAnalysisReviewPersistence.restore(stored).request.operationID == operation)
    }

    @Test func beforeCommitFailureWakeDoesNotCreateWorkAndRetryKeepsIdentity() throws {
        let fixture = try IdentificationHistoryReviewModelTests.Fixture()
        fixture.failSave = true
        let model = fixture.model()
        model.submit(.reject)
        let request = try #require(model.request)
        #expect(fixture.wakes == 1 && fixture.pending == nil)
        model.refresh()
        #expect(fixture.wakes == 1)
        fixture.failSave = false; model.retrySave()
        #expect(fixture.saved == [request, request] && fixture.wakes == 2)
    }
    @Test func committedThrowSurvivesDiskRestartAndDiscoveryKeepsUndoIdentity() throws {
        let support = ObservationAnalysisReviewPersistenceTests()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("review.store")
        let request = try support.request(.undoConfirmation(confirmationOperationID: UUID()))
        func write() throws {
            let container = try support.container(url: url)
            #expect(throws: (any Error).self) {
                try ObservationAnalysisReviewPersistence.stage(request, ownerID: support.owner, container: container,
                    isCurrent: { true }, validateNew: { _ in }, save: { context in
                        try context.save(); throw ObservationHistoryError.unavailable
                    })
            }
        }
        try write()
        let reopened = try support.container(url: url, seed: false)
        let candidates = try ObservationAnalysisReviewPersistence.candidates(container: reopened, ownerID: support.owner)
        let saved = try #require(candidates.first?.0)
        #expect(candidates.count == 1 && saved.request == request)
        let replay = try ObservationAnalysisReviewPersistence.stage(request, ownerID: support.owner, container: reopened,
            isCurrent: { true }, validateNew: { _ in throw ObservationHistoryError.unavailable })
        #expect(replay.request == request && replay.requestSHA256 == saved.requestSHA256)
        let claim = try #require(try ObservationAnalysisReviewPersistence.claim(saved, at: Date(), container: reopened, isCurrent: { true }))
        #expect(claim.intent.request.operationID == request.operationID)
    }

}
