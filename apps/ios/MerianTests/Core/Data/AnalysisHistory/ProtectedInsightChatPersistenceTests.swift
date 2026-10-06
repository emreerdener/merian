import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ProtectedInsightChatPersistenceTests {
    typealias Store = ProtectedInsightChatPersistence
    let source = ObservationHistoryStateSyncTests()

    func seed() async throws -> (ModelContainer, ProtectedInsightChatTicket) {
        let container = try SavedIdentificationDisplayBaselineTests().container()
        _ = try await source.service(data: source.fixture(revision: 10)).syncSelected(observationID: source.support.observation, container: container)
        let context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(source.support.observation, context: context)
        let entry = try ObservationHistoryListingService.entry(UUID(uuidString: source.analysisID)!, scan: scan, context: context)
        return (container, try .init(entry: entry, context: .init(owner: source.support.owner, selected: entry.result.analysisID,
            revision: 10, pendingOperation: nil, undoOperation: nil), observationID: UUID(uuidString: scan.id)!))
    }
    func request(_ ticket: ProtectedInsightChatTicket, text: String = "Synthetic question", id: UUID = UUID()) throws -> ProtectedInsightChatRequest {
        try ticket.request(conversationID: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, clientMessageID: id, normalizedText: text)
    }

    @Test func exactWireAndFingerprintPreserveTextRatherThanNormalizeIt() async throws {
        let (_, ticket) = try await seed(), request = try request(ticket, text: "e\u{301}")
        let restored = try ProtectedInsightChatRequest.decode(request.encoded())
        #expect(restored == request)
        let changed = try self.request(ticket, text: "é", id: request.clientMessageID)
        #expect(changed != request)
        #expect(try ProtectedInsightChatIntent(request: changed, ownerID: ticket.ownerID).requestSHA256
            != ProtectedInsightChatIntent(request: request, ownerID: ticket.ownerID).requestSHA256)
        for text in ["", " padded ", "\u{FEFF}trim", String(repeating: "😀", count: 301)] {
            #expect(throws: (any Error).self) { try self.request(ticket, text: text) }
        }
        #expect(try self.request(ticket, text: String(repeating: "😀", count: 300)).messageText.utf16.count == 600)
        let row = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
        for key in row.keys {
            var changed = row; changed.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try ProtectedInsightChatRequest.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        for (key, value) in [("context_version", true as Any), ("displayed_ticket", NSNull()), ("extra", 1)] {
            var changed = row; changed[key] = value
            #expect(throws: (any Error).self) { try ProtectedInsightChatRequest.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
    }

    @Test func exactReplaySurvivesAuthorityChangeButNewIdentityCannotReplacePendingWork() async throws {
        let (container, ticket) = try await seed(), request = try request(ticket)
        let saved = try Store.stage(request, ticket: ticket, container: container, isCurrent: { true })
        try source.update(container) { scan, _ in scan.observationStateRevision = 11 }
        #expect(try Store.stage(request, ticket: ticket, container: container, isCurrent: { true }).storedData() == saved.storedData())
        #expect(throws: (any Error).self) { try Store.stage(self.request(ticket), ticket: ticket, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.stage(self.request(ticket, text: "Changed", id: request.clientMessageID), ticket: ticket, container: container, isCurrent: { true })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: ["revision", "selection", "owner", "delete", "legacy", "review", "damagedChat"])
    func staleOrPendingAdmissionNeverSaves(change: String) async throws {
        let (container, ticket) = try await seed()
        try source.update(container) { scan, context in
            switch change {
            case "revision": scan.observationStateRevision = 11
            case "selection": scan.selectedAnalysisID = UUID().uuidString.lowercased()
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            case "delete": context.delete(scan)
            case "legacy": context.insert(OfflineJobRecord(id: "legacy", kind: .identificationReviewSync, subjectId: scan.id.lowercased()))
            case "review": context.insert(OfflineJobRecord(id: ObservationAnalysisReviewPersistence.observationPrefix(ticket.observationID) + "damaged",
                kind: .observationAnalysisReviewSync, subjectId: scan.id.lowercased()))
            default: context.insert(OfflineJobRecord(id: "damaged-chat-key", kind: .protectedInsightChatSync, subjectId: scan.id.lowercased()))
            }
        }
        #expect(throws: (any Error).self) { try Store.stage(request(ticket), ticket: ticket, container: container, isCurrent: { true }) }
    }

    @Test func saveFailureAndAccountLossRollbackTheRequest() async throws {
        let (container, ticket) = try await seed(), request = try request(ticket)
        #expect(throws: (any Error).self) {
            try Store.stage(request, ticket: ticket, container: container, isCurrent: { true }, save: { _ in throw Store.IntegrityError.unavailable })
        }
        var checks = 0
        #expect(throws: (any Error).self) {
            try Store.stage(request, ticket: ticket, container: container, isCurrent: { checks += 1; return checks == 1 })
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func diskRestartRetainsExactRequestAndRejectsDamage() async throws {
        let (_, ticket) = try await seed(), request = try request(ticket)
        let intent = try ProtectedInsightChatIntent(request: request, ownerID: ticket.ownerID)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(CurrentSchema.models), url = root.appendingPathComponent("store.sqlite")
        func open() throws -> ModelContainer { try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]) }
        do {
            let container = try open(), context = ModelContext(container)
            context.insert(OfflineJobRecord(id: Store.jobID(request), kind: .protectedInsightChatSync,
                subjectId: request.observationID.uuidString.lowercased(), priority: 65, metadataJSON: String(bytes: try intent.storedData(), encoding: .utf8)))
            try context.save()
        }
        let reopened = try open(), context = ModelContext(reopened)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(try Store.restore(job).storedData() == intent.storedData())
        job.statusRaw = "running"
        #expect(throws: (any Error).self) { try Store.restore(job) }
        job.metadataJSON = "damaged"
        #expect(throws: (any Error).self) { try Store.removeForDeletion(request.observationID.uuidString, context: context, ownerID: ticket.ownerID) }
        try Store.removeForDeletion(request.observationID.uuidString, context: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func terminalReceiptNeverReopensAndFingerprintRejectsMutation() async throws {
        let (container, ticket) = try await seed()
        let request = try request(ticket, id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
        let original = try Store.stage(request, ticket: ticket, container: container, isCurrent: { true })
        let message: [String: Any] = ["id": "9ef24f67-5a9f-8221-b079-90542bb746f9",
            "conversation_id": request.conversationID.uuidString.lowercased(), "scan_id": request.observationID.uuidString.lowercased(),
            "client_message_id": request.clientMessageID.uuidString.lowercased(), "role": "assistant", "text": "Synthetic answer",
            "model": "gemini-2.5-flash", "is_refusal": false, "refusal_reason": NSNull(), "created_at": "2026-10-06T12:00:00Z"]
        let receipt = try JSONSerialization.data(withJSONObject: ["data": ["context_version": 1, "completed": true, "message": message]])
        let completed = try original.accepting(receipt, at: Date(timeIntervalSince1970: 1000))
        #expect(try completed.accepting(receipt, at: Date(timeIntervalSince1970: 2000)).observedAt == completed.observedAt)
        let context = ModelContext(container)
        let storedJob = try context.fetchOfflineJob(id: Store.jobID(request))
        let job = try #require(storedJob)
        job.metadataJSON = String(bytes: try completed.storedData(), encoding: .utf8); job.status = .complete
        try context.save()
        #expect(try Store.stage(request, ticket: ticket, container: container, isCurrent: { true }).isComplete)
        let reopened = try ProtectedInsightChatIntent.decode(completed.storedData())
        #expect(reopened.receiptData == completed.receiptData && reopened.request == request)
        var row = try #require(JSONSerialization.jsonObject(with: original.storedData()) as? [String: Any])
        row["request_sha256"] = String(repeating: "a", count: 64)
        #expect(throws: (any Error).self) { try ProtectedInsightChatIntent.decode(JSONSerialization.data(withJSONObject: row)) }
    }

    @Test func revisionMaximumMatchesServer() throws {
        let id = UUID()
        #expect(try ProtectedInsightChatRequest.Selection(analysisID: id, stateRevision: 2_147_483_646, reviewRevision: 0).stateRevision == 2_147_483_646)
        #expect(throws: (any Error).self) { try ProtectedInsightChatRequest.Selection(analysisID: id, stateRevision: 2_147_483_647, reviewRevision: 0) }
    }

    @Test(arguments: ["serverStatus", "serverStage", "serverRetryAfter", "priority", "bytes", "network", "cellular"])
    func inertJobsRejectRemoteOrExecutionState(field: String) async throws {
        let (container, ticket) = try await seed(), request = try request(ticket)
        _ = try Store.stage(request, ticket: ticket, container: container, isCurrent: { true })
        let context = ModelContext(container), rows = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        let job = try #require(rows.first)
        switch field {
        case "serverStatus": job.serverStatus = "complete"
        case "serverStage": job.serverStage = "dispatched"
        case "serverRetryAfter": job.serverRetryAfter = Date()
        case "priority": job.priority = 0
        case "bytes": job.approximateBytes = 1
        case "network": job.requiresUnconstrainedNetwork = true
        default: job.allowsCellular = false
        }
        #expect(throws: (any Error).self) { try Store.restore(job) }
    }

    @Test func erasureUsesSubjectOnlyWhenCanonicalNamespaceIsUnavailable() async throws {
        let (container, ticket) = try await seed(), context = ModelContext(container)
        let other = UUID(), subject = ticket.observationID.uuidString.lowercased()
        let malformed = OfflineJobRecord(id: "damaged-chat-key", kind: .protectedInsightChatSync, subjectId: subject, metadataJSON: "private synthetic text")
        let different = OfflineJobRecord(id: "other-damaged-key", kind: .protectedInsightChatSync, subjectId: other.uuidString.lowercased())
        let canonicalOther = OfflineJobRecord(id: Store.observationPrefix(other) + UUID().uuidString.lowercased(), kind: .protectedInsightChatSync,
            subjectId: subject, metadataJSON: "damaged subject must not authorize deleting this other namespace")
        context.insert(malformed); context.insert(different); context.insert(canonicalOther); try context.save()
        #expect(throws: (any Error).self) { try Store.removeForDeletion(subject, context: context, ownerID: ticket.ownerID) }
        try Store.removeForDeletion(subject, context: context); try context.save()
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2)
        #expect(try context.fetch(FetchDescriptor<OfflineJobRecord>()).allSatisfy { $0.id != "damaged-chat-key" })
    }

    @Test func historicalPreviewCannotBecomeSelectedChatTicket() async throws {
        let (container, ticket) = try await seed(), context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(source.support.observation, context: context)
        let entry = try ObservationHistoryListingService.entry(ticket.selection.analysisID, scan: scan, context: context)
        #expect(throws: (any Error).self) {
            try ProtectedInsightChatTicket(entry: entry, context: .init(owner: ticket.ownerID, selected: UUID(), revision: 10,
                pendingOperation: nil, undoOperation: nil), observationID: ticket.observationID)
        }
    }
}
