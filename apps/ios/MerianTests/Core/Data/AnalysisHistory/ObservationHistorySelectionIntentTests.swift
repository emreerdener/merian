import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationHistorySelectionIntentTests {
    let support = ObservationHistorySelectionSyncTests()
    var observation: String { support.support.support.observation }
    var owner: UUID { support.support.support.owner }
    var target: UUID { UUID(uuidString: support.otherID)! }
    typealias Intent = ObservationHistorySelectionIntent
    typealias Failure = ObservationHistoryStateSyncService.AdmissionError

    func seeded() async throws -> ModelContainer {
        let container = try await support.seeded()
        var value = try JSONSerialization.jsonObject(with: support.nativeResponse(revision: 10)) as! [String: Any]
        value["selected_analysis_id"] = support.support.analysisID
        var cloud = support.support.support.client(fetch: { _ in Data() })
        cloud.fetchState = { _ in try support.support.support.bytes(value) }
        _ = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: observation, analysisID: target, container: container)
        return container
    }

    func receipt(_ request: ObservationHistorySelectionRequest, previous: String? = nil) throws -> Data {
        try JSONEncoder().encode(ObservationHistorySelectionReceipt(schema_version: 1, operation_id: request.operation_id,
            observation_id: request.observation_id, previous_analysis_id: previous ?? support.support.analysisID,
            selected_analysis_id: request.analysis_id, observation_revision: request.expected_observation_revision + 1,
            review_revision: request.expected_review_revision))
    }

    func service(state: Data? = nil, duringSelect: @escaping (ObservationHistorySelectionRequest) throws -> Void = { _ in },
                 duringRead: @escaping () throws -> Void = {}, current: @escaping () -> Bool = { true }) -> ObservationHistorySelectionService {
        var cloud = support.support.support.client(fetch: { _ in Data() }, current: current)
        cloud.select = { request in try duringSelect(request); return try receipt(request) }
        cloud.fetchState = { request in
            #expect(request.analysis_id == nil && request.observation_id == observation)
            try duringRead()
            return try state ?? support.nativeResponse()
        }
        return .init(cloud: cloud)
    }

    @discardableResult
    func prepare(_ container: ModelContainer, service: ObservationHistorySelectionService? = nil) throws -> ObservationHistorySelectionRequest {
        try (service ?? self.service()).prepare(observationID: observation, analysisID: target, ownerID: owner, container: container)
    }

    func entry(_ container: ModelContainer) throws -> Intent.Entry {
        try #require(try Intent.load(observation, context: ModelContext(container)))
    }

    @Test func sharedSelectionReceiptRejectsUnknownMismatchedAndNonIntegerFields() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/selection-v1.json")
        let fixture = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let request = try JSONDecoder().decode(ObservationHistorySelectionRequest.self, from: JSONSerialization.data(withJSONObject: fixture["request"]!))
        let bytes = try JSONSerialization.data(withJSONObject: fixture["receipt"]!)
        #expect(try ObservationHistorySelectionReceipt.decode(bytes, request: request, previous: support.support.analysisID).observation_revision == 11)
        for (key, value) in [("operation_id", UUID().uuidString.lowercased() as Any), ("previous_analysis_id", support.otherID),
                             ("selected_analysis_id", observation), ("observation_revision", 12), ("review_revision", 1),
                             ("schema_version", true), ("review_revision", 0.5), ("extra", 1)] {
            var row = fixture["receipt"] as! [String: Any]; row[key] = value
            #expect(throws: (any Error).self) { try ObservationHistorySelectionReceipt.decode(JSONSerialization.data(withJSONObject: row), request: request, previous: support.support.analysisID) }
        }
    }

    @Test func stagingDoesNotSelectAndAmbiguousRetryReusesExactRequest() async throws {
        let container = try await seeded(), request = try prepare(container)
        #expect(try support.parent(container).selectedAnalysisID == support.support.analysisID)
        #expect(try entry(container).receipt == nil)
        var seen: [ObservationHistorySelectionRequest] = []
        await #expect(throws: ObservationHistoryError.unavailable) {
            try await service(duringSelect: { seen.append($0); throw ObservationHistoryError.unavailable }).sendPending(observationID: observation, container: container)
        }
        _ = try await service(duringSelect: { seen.append($0) }).sendPending(observationID: observation, container: container)
        #expect(seen == [request, request])
        #expect(try entry(container).receipt?.operation_id == request.operation_id)
        #expect(try support.parent(container).selectedAnalysisID == support.otherID)
        #expect(try support.parent(container).localAIIdentificationReview.authority == nil)
        #expect(try support.parent(container).fieldNotes == "Preserved private note")
    }

    @Test func acknowledgedReceiptSupportsRevisionBoundUndoAndKeepsEachOwnAuthority() async throws {
        let container = try await seeded(); try prepare(container)
        _ = try await service().sendPending(observationID: observation, container: container)
        let originalOperation = try entry(container).request.operation_id
        let undo = try service().prepareUndo(observationID: observation, operationID: UUID(uuidString: try entry(container).request.operation_id)!, ownerID: owner, container: container)
        #expect(undo.analysis_id == support.support.analysisID && undo.expected_observation_revision == 11 && undo.expected_review_revision == 3)
        var back = service(state: try support.savedResponse(revision: 12))
        back.cloud.select = { request in try receipt(request, previous: support.otherID) }
        _ = try await back.sendPending(observationID: observation, container: container)
        #expect(try support.parent(container).scientificName == "Preserved correction")
        #expect(try support.parent(container).localAIIdentificationReview.authority?.state == .aiRejected)
        #expect(try support.parent(container).observationStateRevision == 12)
        #expect(try entry(container).receipt?.observation_revision == 12)
        #expect(throws: Intent.Failure.staleUndo) {
            try service().prepareUndo(observationID: observation, operationID: UUID(uuidString: originalOperation)!, ownerID: owner, container: container)
        }
    }

    @Test func delayedReceiptReadsCurrentAuthorityAndCannotEnableStaleUndo() async throws {
        let container = try await seeded(); try prepare(container)
        // Server selected B at 11, then another device selected A at 12.
        _ = try await service(state: support.savedResponse(revision: 12)).sendPending(observationID: observation, container: container)
        #expect(try support.parent(container).selectedAnalysisID == support.support.analysisID)
        #expect(try support.parent(container).observationStateRevision == 12)
        #expect(try entry(container).receipt?.observation_revision == 11)
        #expect(throws: Intent.Failure.staleUndo) { try service().prepareUndo(observationID: observation, operationID: UUID(uuidString: try entry(container).request.operation_id)!, ownerID: owner, container: container) }
        await #expect(throws: Failure.staleRevision) {
            try await support.support.service(data: support.nativeResponse()).syncSelected(observationID: observation, container: container)
        }
    }

    @Test func finalSaveFailureRollsBackProjectionAndReceiptTogether() async throws {
        let container = try await seeded(); try prepare(container)
        var failing = service(); failing.save = { _ in throw ObservationHistoryError.unavailable }
        await #expect(throws: ObservationHistoryError.unavailable) { try await failing.sendPending(observationID: observation, container: container) }
        #expect(try entry(container).receipt == nil)
        #expect(try support.parent(container).selectedAnalysisID == support.support.analysisID && support.parent(container).observationStateRevision == 10)
        _ = try await service().sendPending(observationID: observation, container: container)
        #expect(try entry(container).receipt != nil)
    }

    @Test func failedStagingDoesNotLeavePartialIntentAndPendingRequestCannotBeReplaced() async throws {
        let container = try await seeded()
        var failing = service(); failing.save = { _ in throw ObservationHistoryError.unavailable }
        #expect(throws: ObservationHistoryError.unavailable) { try prepare(container, service: failing) }
        #expect(try Intent.load(observation, context: ModelContext(container)) == nil)
        let request = try prepare(container)
        #expect(throws: Intent.Failure.pendingSelection) { try prepare(container) }
        #expect(try entry(container).request == request)
        await #expect(throws: Intent.Failure.pendingSelection) {
            try await support.support.service(data: support.nativeResponse()).syncSelected(observationID: observation, container: container)
        }
    }

    @Test func malformedTerminalAndWrongGenerationIntentsFailClosed() async throws {
        for corruption in 0..<5 {
            let container = try await seeded(); try prepare(container)
            let context = ModelContext(container)
            let job = try #require(try context.fetchOfflineJob(id: Intent.jobID(observation)))
            switch corruption {
            case 0: job.metadataJSON = "{}"
            case 1: job.status = .cancelled
            case 2: job.kind = .scanIngestion
            case 3: job.subjectId = UUID().uuidString
            default: job.metadataJSON = String(repeating: "x", count: 8_193)
            }
            try context.save()
            var called = false
            await #expect(throws: (any Error).self) {
                try await service(duringSelect: { _ in called = true }).sendPending(observationID: observation, container: container)
            }
            #expect(!called)
            #expect(throws: (any Error).self) { try prepare(container) }
        }
        let container = try await seeded(); try prepare(container)
        await #expect(throws: Intent.Failure.invalidIntent) {
            try await service(duringRead: {
                let context = ModelContext(container), old = try entry(container)
                let replacement = Intent.Entry(version: 1, owner: old.owner, previous: old.previous, previousReview: old.previousReview,
                    request: .init(observation: UUID(uuidString: observation)!, analysis: target, revision: 10, review: 0))
                try Intent.store(replacement, context: context); try context.save()
            }).sendPending(observationID: observation, container: container)
        }
        #expect(try support.parent(container).observationStateRevision == 10)
    }

    @Test func accountAndLocalReviewChangesAcrossSuspensionKeepPendingIntent() async throws {
        for failedCheck in 1...5 {
            let container = try await seeded(); try prepare(container)
            var checks = 0
            await #expect(throws: ObservationHistoryError.accountChanged) {
                try await service(current: { checks += 1; return checks != failedCheck }).sendPending(observationID: observation, container: container)
            }
            #expect(try entry(container).receipt == nil && support.parent(container).observationStateRevision == 10)
        }
        let container = try await seeded(); try prepare(container)
        await #expect(throws: Failure.pendingReview) {
            try await service(duringRead: {
                try support.support.update(container) { scan, context in
                    context.insert(OfflineJobRecord(id: "synthetic-review", kind: .identificationReviewSync, subjectId: scan.id))
                }
            }).sendPending(observationID: observation, container: container)
        }
        #expect(try entry(container).receipt == nil)
    }

    @Test func explicitDeletionClearsSelectionPayloadAndRejectsLateReceipt() async throws {
        let container = try await seeded(); try prepare(container)
        await #expect(throws: (any Error).self) {
            try await service(duringRead: {
                try ConfirmedSpeciesReviewPersistence.transaction {
                    let context = ModelContext(container)
                    let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
                    try ObservationHistoryEnrollmentIntent.supersedeForExplicitDeletion(observation, context: context)
                    context.delete(scan); try context.save()
                }
            }).sendPending(observationID: observation, container: container)
        }
        #expect(try Intent.load(observation, context: ModelContext(container)) == nil)
        #expect(try ObservationHistoryEnrollmentIntent.holds(observation, context: ModelContext(container)))
        #expect(try support.support.support.count(container) == 0)
    }

    @Test func staleTargetAndStaleUndoAfterAuthorityRefreshCannotDispatch() async throws {
        let container = try await seeded()
        _ = try await support.support.service(data: support.savedResponse(revision: 11)).syncSelected(observationID: observation, container: container)
        #expect(throws: Failure.staleRevision) { try prepare(container) }
        let other = try await seeded(); try prepare(other)
        _ = try await service().sendPending(observationID: observation, container: other)
        _ = try await support.support.service(data: support.nativeResponse(revision: 12)).syncSelected(observationID: observation, container: other)
        #expect(throws: Intent.Failure.staleUndo) { try service().prepareUndo(observationID: observation, operationID: UUID(uuidString: try entry(other).request.operation_id)!, ownerID: owner, container: other) }
    }

    @Test func pendingIdentitySurvivesDiskReopenAndNeverSchedulesEvenIfDamaged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("selection.sqlite"))
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: [configuration])
        let entry = Intent.Entry(version: 1, owner: owner.uuidString.lowercased(), previous: support.support.analysisID, previousReview: 3,
            request: .init(observation: UUID(uuidString: observation)!, analysis: target, revision: 10, review: 0))
        do { let context = ModelContext(container!); try Intent.store(entry, context: context); try context.save() }
        container = nil
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        #expect(try Intent.load(observation, context: ModelContext(reopened)) == entry)
        let context = ModelContext(reopened)
        let job = try #require(try context.fetchOfflineJob(id: Intent.jobID(observation)))
        job.status = .pending; job.nextRunAt = .distantPast; try context.save()
        let manager = OfflineQueueManager.shared, previous = manager.modelContext
        defer { manager.modelContext = previous }
        manager.modelContext = context
        #expect(OfflineJobScheduler.shared.nextPersistedWakeDate(using: manager) == nil)
    }

    @Test func newerTargetAuthorityIsAdmittedInsteadOfOldReceiptAuthority() async throws {
        let container = try await seeded(); try prepare(container)
        let current = try support.replacingReview(support.nativeResponse(revision: 12), outer: 1, ai: 1)
        _ = try await service(state: current).sendPending(observationID: observation, container: container)
        let scan = try support.parent(container)
        #expect(scan.selectedAnalysisID == support.otherID && scan.observationStateRevision == 12)
        #expect(scan.localAIIdentificationReview.authority?.revision == 1 && scan.localAIIdentificationReview.authority?.state == .aiRejected)
        #expect(try entry(container).receipt?.review_revision == 0)
        #expect(throws: Intent.Failure.staleUndo) { try service().prepareUndo(observationID: observation, operationID: UUID(uuidString: try entry(container).request.operation_id)!, ownerID: owner, container: container) }
    }

    @Test func deletionAfterAcknowledgmentErasesCompletedReceiptPayload() async throws {
        let container = try await seeded(); try prepare(container)
        _ = try await service().sendPending(observationID: observation, container: container)
        try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
            try ObservationHistoryEnrollmentIntent.supersedeForExplicitDeletion(observation, context: context)
            context.delete(scan); try context.save()
        }
        let verify = ModelContext(container)
        #expect(try Intent.load(observation, context: verify) == nil)
        let fence = try #require(try verify.fetchOfflineJob(id: ObservationHistoryEnrollmentIntent.jobID(observation)))
        #expect(fence.status == .cancelled && fence.metadataJSON == nil)
        #expect(try verify.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
    }

    @Test func invalidReceiptFailedReadAndOlderReadRetainPendingIdentity() async throws {
        for failure in 0..<4 {
            let container = try await seeded(), request = try prepare(container)
            var failing = service()
            switch failure {
            case 0: failing.cloud.select = { _ in Data("{}".utf8) }
            case 1: failing.cloud.fetchState = { _ in throw ObservationHistoryError.unavailable }
            case 2: failing.cloud.fetchState = { _ in try support.nativeResponse(revision: 10) }
            default: failing.cloud.fetchState = { _ in try support.savedResponse(revision: 11) }
            }
            await #expect(throws: (any Error).self) { try await failing.sendPending(observationID: observation, container: container) }
            #expect(try entry(container).request == request && entry(container).receipt == nil)
            #expect(try support.parent(container).observationStateRevision == 10)
        }
    }

    @Test func foreignStoredOwnerCannotDispatchUnderCurrentAccount() async throws {
        let container = try await seeded(); try prepare(container)
        let foreign = UUID(), context = ModelContext(container), old = try entry(container)
        try Intent.store(.init(version: 1, owner: foreign.uuidString.lowercased(), previous: old.previous,
            previousReview: old.previousReview, request: old.request), context: context)
        try context.save()
        var called = false, failing = service(duringSelect: { _ in called = true })
        failing.cloud.begin = { expected in
            #expect(expected == foreign)
            throw ObservationHistoryError.accountChanged
        }
        await #expect(throws: ObservationHistoryError.accountChanged) { try await failing.sendPending(observationID: observation, container: container) }
        #expect(!called)
        #expect(try entry(container).receipt == nil)
        #expect(throws: Intent.Failure.pendingSelection) { try prepare(container) }
    }

    func rejectedService(state: Data? = nil) -> ObservationHistorySelectionService {
        var client = service(state: state)
        client.cloud.select = { request in
            try JSONEncoder().encode(ObservationHistorySelectionRejection(schema_version: 1,
                operation_id: request.operation_id, observation_id: request.observation_id, analysis_id: request.analysis_id,
                expected_observation_revision: request.expected_observation_revision,
                expected_review_revision: request.expected_review_revision, outcome: "revision_conflict"))
        }
        return client
    }

    @Test func sharedRejectionBindsEveryRequestFieldAndContainsNoAuthority() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/selection-v1.json")
        let fixture = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let request = try JSONDecoder().decode(ObservationHistorySelectionRequest.self, from: JSONSerialization.data(withJSONObject: fixture["request"]!))
        let bytes = try JSONSerialization.data(withJSONObject: fixture["rejection"]!)
        if case .rejected = try ObservationHistorySelectionOutcome.decode(bytes, request: request, previous: support.support.analysisID) {} else { Issue.record("Expected rejection") }
        for (key, value) in [("operation_id", UUID().uuidString.lowercased() as Any), ("observation_id", support.otherID),
                             ("analysis_id", observation), ("expected_observation_revision", 12), ("expected_review_revision", 1),
                             ("schema_version", true), ("expected_review_revision", 0.5), ("outcome", "unavailable"), ("extra", 1)] {
            var row = fixture["rejection"] as! [String: Any]; row[key] = value
            #expect(throws: (any Error).self) { try ObservationHistorySelectionOutcome.decode(JSONSerialization.data(withJSONObject: row), request: request, previous: support.support.analysisID) }
        }
    }

    @Test func definitiveConflictAdmitsCurrentAuthorityAndRetiresWithoutUndo() async throws {
        let container = try await seeded(), request = try prepare(container)
        let result = try await rejectedService(state: support.savedResponse(revision: 12)).sendPending(observationID: observation, container: container)
        if case .rejected = result {} else { Issue.record("Expected durable rejection") }
        let stored = try entry(container)
        #expect(stored.version == 2 && stored.receipt == nil && stored.rejection?.operation_id == request.operation_id)
        let context = ModelContext(container)
        #expect(try context.fetchOfflineJob(id: Intent.jobID(observation))?.status == .cancelled)
        #expect(try support.parent(container).selectedAnalysisID == support.support.analysisID)
        #expect(try support.parent(container).observationStateRevision == 12)
        #expect(throws: Intent.Failure.staleUndo) { try service().prepareUndo(observationID: observation, operationID: UUID(uuidString: request.operation_id)!, ownerID: owner, container: container) }
        // A fresh preview is mandatory before a new operation can replace the rejected one.
        #expect(throws: Failure.staleRevision) { try prepare(container) }
        var value = try JSONSerialization.jsonObject(with: support.nativeResponse(revision: 12)) as! [String: Any]
        value["selected_analysis_id"] = support.support.analysisID
        var cloud = support.support.support.client(fetch: { _ in Data() })
        cloud.fetchState = { _ in try support.support.support.bytes(value) }
        _ = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: observation, analysisID: target, container: container)
        let replacement = try prepare(container)
        #expect(replacement.operation_id != request.operation_id && replacement.expected_observation_revision == 12)
    }

    @Test func conflictReadOrSaveFailureKeepsExactPendingRequestForRecovery() async throws {
        for failure in 0..<3 {
            let container = try await seeded(), request = try prepare(container)
            var client = rejectedService(state: try support.savedResponse(revision: 12))
            if failure == 0 { client.cloud.fetchState = { _ in throw ObservationHistoryError.unavailable } }
            else if failure == 1 { client.save = { _ in throw ObservationHistoryError.unavailable } }
            else { client.cloud.fetchState = { _ in try support.savedResponse(revision: 9) } }
            await #expect(throws: (any Error).self) { try await client.sendPending(observationID: observation, container: container) }
            #expect(try entry(container).request == request && entry(container).rejection == nil)
            #expect(try support.parent(container).observationStateRevision == 10)
            _ = try await rejectedService(state: support.savedResponse(revision: 12)).sendPending(observationID: observation, container: container)
            #expect(try entry(container).rejection?.operation_id == request.operation_id)
        }
    }

    @Test func unprovenCancellationAndDowngradedRejectionFailClosed() async throws {
        let container = try await seeded(); try prepare(container)
        let context = ModelContext(container), job = try #require(try context.fetchOfflineJob(id: Intent.jobID(observation)))
        job.status = .cancelled; try context.save()
        #expect(throws: Intent.Failure.invalidIntent) { try Intent.requireIdle(observation, context: ModelContext(container)) }
        job.status = .needsAttention; try context.save()
        _ = try await rejectedService(state: support.savedResponse(revision: 12)).sendPending(observationID: observation, container: container)
        let fresh = ModelContext(container), completed = try #require(try fresh.fetchOfflineJob(id: Intent.jobID(observation)))
        var payload = try JSONSerialization.jsonObject(with: Data(try #require(completed.metadataJSON).utf8)) as! [String: Any]
        payload["version"] = 1
        completed.metadataJSON = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)
        try fresh.save()
        #expect(throws: Intent.Failure.invalidIntent) { try Intent.requireIdle(observation, context: ModelContext(container)) }
    }

}
