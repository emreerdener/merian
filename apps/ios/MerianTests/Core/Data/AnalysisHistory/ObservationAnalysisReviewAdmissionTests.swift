import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAnalysisReviewAdmissionTests {
    let source = ObservationHistoryStateSyncTests()
    typealias Store = ObservationAnalysisReviewPersistence

    func seed(audio: Bool = false) async throws -> (ModelContainer, ObservationAnalysisReviewTicket) {
        let container = try SavedIdentificationDisplayBaselineTests().container()
        _ = try await source.service(data: audio ? audioState(source.fixture(revision: 10)) : source.fixture(revision: 10)).syncSelected(observationID: source.support.observation, container: container)
        let context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(source.support.observation, context: context)
        let entry = try ObservationHistoryListingService.entry(UUID(uuidString: source.analysisID)!, scan: scan, context: context)
        return (container, try .init(entry: entry, context: .init(owner: source.support.owner, selected: entry.result.analysisID,
            revision: 10, pendingOperation: nil, undoOperation: nil), observationID: UUID(uuidString: scan.id)!))
    }
    func audioState(_ data: Data) throws -> Data {
        var state = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var item = try #require(state["analysis"] as? [String: Any])
        let text = try #require(item["snapshot"] as? String)
        let original = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        var snapshot = try ObservationHistorySyncTests().audioSnapshot()
        snapshot["observation_id"] = original["observation_id"]; snapshot["analysis_id"] = original["analysis_id"]
        snapshot["ordinal"] = original["ordinal"]; snapshot["source_analysis_id"] = NSNull()
        item["snapshot"] = String(decoding: try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), as: UTF8.self)
        state["analysis"] = item
        return try JSONSerialization.data(withJSONObject: state)
    }
    func stage(_ ticket: ObservationAnalysisReviewTicket, in container: ModelContainer,
               operation: UUID = UUID()) throws -> ObservationAnalysisReviewIntent {
        try ObservationAnalysisReviewAdmission.stage(ticket.request(.reject, operationID: operation), ticket: ticket,
            container: container, isCurrent: { true })
    }
    func status(_ intent: ObservationAnalysisReviewIntent, in container: ModelContainer) throws -> ObservationAnalysisReviewStatus? {
        try ObservationAnalysisReviewStatus.read(operationID: intent.request.operationID, ownerID: intent.ownerID,
            observationID: intent.request.observationID, analysisID: intent.request.analysisID, container: container, isCurrent: { true })
    }

    @Test(arguments: [false, true]) func immutableTapStagesWithoutChangingSelectionAndExactReplaySurvivesRevisionChange(audio: Bool) async throws {
        let (container, ticket) = try await seed(audio: audio), request = try ticket.request(.reject, operationID: UUID())
        let intent = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: { true })
        #expect(try status(intent, in: container)?.phase == .pending)
        #expect(try ObservationAnalysisReviewStatus.pending(ownerID: ticket.ownerID, observationID: ticket.observationID,
            container: container, isCurrent: { true })?.operationID == request.operationID)
        try source.update(container) { scan, _ in
            #expect(scan.selectedAnalysisID == ticket.selectedAnalysisID.uuidString.lowercased())
            scan.observationStateRevision = 11
        }
        let replay = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: { true })
        #expect(replay.request == request)
        #expect(throws: (any Error).self) { try stage(ticket, in: container) }
    }

    @Test(arguments: ["global", "selection", "authority", "owner", "legacy", "delete"], [false, true])
    func changedDisplayedBaselineNeverStages(change: String, audio: Bool) async throws {
        let (container, ticket) = try await seed(audio: audio)
        try source.update(container) { scan, context in
            switch change {
            case "global": scan.observationStateRevision = 11
            case "selection": scan.selectedAnalysisID = UUID().uuidString.lowercased()
            case "authority":
                let state = try #require(scan.analysisRecords?.first?.state)
                var row = try #require(JSONSerialization.jsonObject(with: state.reviewSnapshotData) as? [String: Any])
                row["user_review_state"] = "ai_confirmed"
                scan.observationStateRevision = 11
                try state.update(observationStateRevision: 11, reviewRevision: 1,
                    reviewSnapshotData: JSONSerialization.data(withJSONObject: row), displaySnapshotData: state.displaySnapshotData)
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            case "legacy": context.insert(OfflineJobRecord(id: "synthetic-review", kind: .identificationReviewSync, subjectId: scan.id.lowercased()))
            default: context.delete(scan)
            }
        }
        #expect(throws: (any Error).self) { try stage(ticket, in: container) }
        #expect(try ModelContext(container).fetch(FetchDescriptor<OfflineJobRecord>()).allSatisfy { !$0.id.hasPrefix(Store.prefix) })
    }

    @Test func sameIdentityAndRevisionsCannotAuthorizeDifferentImmutableResultBytes() async throws {
        let (_, ticket) = try await seed()
        let container = try SavedIdentificationDisplayBaselineTests().container()
        var row = try #require(JSONSerialization.jsonObject(with: source.fixture(revision: 10)) as? [String: Any])
        var item = try #require(row["analysis"] as? [String: Any])
        let text = try #require(item["snapshot"] as? String)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        var result = try #require(envelope["result"] as? [String: Any])
        result["ai_reasoning"] = "A different immutable synthetic answer."
        envelope["result"] = result
        item["snapshot"] = String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
        row["analysis"] = item
        _ = try await source.service(data: JSONSerialization.data(withJSONObject: row)).syncSelected(
            observationID: source.support.observation, container: container)
        #expect(throws: (any Error).self) { try stage(ticket, in: container) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func saveFailureAccountLossAndRequestSubstitutionDoNotCreateWork() async throws {
        let (container, ticket) = try await seed(), request = try ticket.request(.reject, operationID: UUID())
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: { true },
                save: { _ in throw Store.IntegrityError.unavailable })
        }
        var checks = 0
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container,
                isCurrent: { checks += 1; return checks == 1 })
        }
        let changed = try ObservationAnalysisReviewRequest(observationID: ticket.observationID, analysisID: ticket.analysisID,
            operationID: request.operationID, expectedObservationRevision: 11, expectedReviewRevision: 0, decision: .reject)
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewAdmission.stage(changed, ticket: ticket, container: container, isCurrent: { true })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func danglingChildNeverExposesAnOperationStatus() async throws {
        let (container, ticket) = try await seed(), intent = try stage(ticket, in: container)
        let context = ModelContext(container)
        let child = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        context.delete(child); try context.save()
        #expect(throws: (any Error).self) { try status(intent, in: container) }
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewStatus.pending(ownerID: ticket.ownerID, observationID: ticket.observationID,
                container: container, isCurrent: { true })
        }
    }

    @Test func statusIsOwnerTargetAndDeletionFencedAndHoldsRemainHeld() async throws {
        let (container, ticket) = try await seed(), intent = try stage(ticket, in: container)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let claim = try #require(try Store.claim(intent, at: now, container: container, isCurrent: { true }))
        try Store.retry(claim, at: now, needsAttention: true, container: container, isCurrent: { true })
        #expect(try status(intent, in: container)?.phase == .needsAttention)
        #expect(try stage(ticket, in: container, operation: intent.request.operationID).request == intent.request)
        #expect(try status(intent, in: container)?.phase == .needsAttention)
        for (owner, target) in [(UUID(), ticket.analysisID), (ticket.ownerID, UUID())] {
            #expect(throws: (any Error).self) {
                try ObservationAnalysisReviewStatus.read(operationID: intent.request.operationID, ownerID: owner,
                    observationID: ticket.observationID, analysisID: target, container: container, isCurrent: { true })
            }
        }
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewStatus.pending(ownerID: ticket.ownerID, observationID: ticket.observationID,
                container: container, isCurrent: { false })
        }
        try source.update(container) { scan, context in context.delete(scan) }
        #expect(throws: (any Error).self) { try status(intent, in: container) }
    }
    @Test func audioPublicationFailsBeforeAnyAccountOrNetworkWork() async throws {
        let (container, ticket) = try await seed(audio: true)
        var cloud = source.support.client(fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.begin = { _ in Issue.record("Audio publication acquired a lease"); throw ObservationHistoryError.unavailable }
        let service = ObservationPublicationConsentService(cloud: cloud, fetch: { _, _ in
            Issue.record("Audio publication fetched photo consent"); throw ObservationHistoryError.unavailable
        })
        await #expect(throws: ObservationHistoryError.unavailable) {
            try await service.prepare(ticket: ticket, container: container, isCurrent: { true })
        }
    }

}
