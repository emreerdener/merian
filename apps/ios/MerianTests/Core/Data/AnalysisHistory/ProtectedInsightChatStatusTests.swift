import CryptoKit
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ProtectedInsightChatStatusTests {
    typealias Store = ProtectedInsightChatPersistence
    let support = ProtectedInsightChatPersistenceTests()

    func page(_ ticket: ProtectedInsightChatTicket, _ container: ModelContainer, after: UUID? = nil) throws -> Store.StatusPage {
        try Store.status(ownerID: ticket.ownerID, observationID: ticket.observationID, afterMessageID: after,
            container: container, isCurrent: { true })
    }
    func insert(_ index: Int, ticket: ProtectedInsightChatTicket, context: ModelContext, complete: Bool = true) throws {
        let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
        let request = try support.request(ticket, id: id)
        var intent = try ProtectedInsightChatIntent(request: request, ownerID: ticket.ownerID)
        if complete { intent = try intent.accepting(receipt(intent), at: Date(timeIntervalSince1970: 1000)) }
        context.insert(OfflineJobRecord(id: Store.jobID(request), kind: .protectedInsightChatSync,
            subjectId: ticket.observationID.uuidString.lowercased(), priority: 65, status: complete ? .complete : .pending, metadataJSON: String(bytes: try intent.storedData(), encoding: .utf8)))
    }

    func receipt(_ intent: ProtectedInsightChatIntent) throws -> Data {
        var envelope = try #require(JSONSerialization.jsonObject(with: ProtectedInsightChatClaimsTests().receipt(intent)) as? [String: Any])
        var data = try #require(envelope["data"] as? [String: Any])
        var message = try #require(data["message"] as? [String: Any])
        let source = "merian-field-chat-assistant-v1:" + intent.request.conversationID.uuidString.lowercased()
            + ":" + intent.request.clientMessageID.uuidString.lowercased()
        var bytes = Array(SHA256.hash(data: Data(source.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80; bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        message["id"] = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map {
            String(hex.dropFirst($0.lowerBound).prefix($0.count))
        }.joined(separator: "-")
        data["message"] = message; envelope["data"] = data
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    @Test func pagesAreCanonicalAndStillFindUnfinishedBeyondTheirBoundary() async throws {
        let (container, ticket) = try await support.seed(), context = ModelContext(container)
        for index in (1...70).reversed() { try insert(index, ticket: ticket, context: context, complete: index != 70) }
        try context.save()
        let first = try page(ticket, container)
        #expect(first.completed.count == 20 && first.unfinished?.state == .pending)
        #expect(first.completed.first?.request.clientMessageID.uuidString.hasSuffix("000000000001") == true)
        let second = try page(ticket, container, after: first.nextAfterMessageID)
        #expect(second.completed.count == 20 && second.completed.first?.request.clientMessageID.uuidString.hasSuffix("000000000021") == true)
        #expect(second.unfinished?.intent.request == first.unfinished?.intent.request)
        let third = try page(ticket, container, after: second.nextAfterMessageID)
        let fourth = try page(ticket, container, after: third.nextAfterMessageID)
        #expect(fourth.completed.count == 9 && fourth.nextAfterMessageID == nil)
        #expect(throws: (any Error).self) { try Store.stage(support.request(ticket), ticket: ticket, container: container, isCurrent: { true }) }
        try support.source.update(container) { scan, _ in scan.observationStateRevision = 11; scan.selectedAnalysisID = UUID().uuidString.lowercased() }
        #expect(try page(ticket, container).completed.count == 20) // Historical requests never rebase.
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 70)
    }

    @Test(arguments: ["malformedComplete", "twoPending", "wrongKind", "wrongChild", "wrongOwner", "damagedSubject"])
    func offPageDamageCannotLookVacant(change: String) async throws {
        let (container, ticket) = try await support.seed(), context = ModelContext(container)
        for index in 1...65 { try insert(index, ticket: ticket, context: context, complete: change != "twoPending" || index != 1) }
        try insert(66, ticket: ticket, context: context, complete: change != "twoPending")
        try context.save()
        let rows = try context.fetch(FetchDescriptor<OfflineJobRecord>(sortBy: [SortDescriptor(\OfflineJobRecord.id)]))
        let row = try #require(rows.last)
        switch change {
        case "malformedComplete": row.metadataJSON = "damaged"
        case "wrongKind": row.kindRaw = "unknown"
        case "wrongChild": for child in try context.fetch(FetchDescriptor<LocalAnalysisRecord>()) { context.delete(child) }
        case "wrongOwner":
            let scan = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: context)
            scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
        case "damagedSubject":
            context.insert(OfflineJobRecord(id: "broken", kind: .protectedInsightChatSync, subjectId: ticket.observationID.uuidString.uppercased()))
        default: break
        }
        try context.save()
        #expect(throws: (any Error).self) { try page(ticket, container) }
    }

    @Test func canonicalOtherNamespaceWinsAndOwnerLossDeletionAndLimitsDeny() async throws {
        let (container, ticket) = try await support.seed(), context = ModelContext(container)
        context.insert(OfflineJobRecord(id: Store.observationPrefix(UUID()) + UUID().uuidString.lowercased(),
            kind: .protectedInsightChatSync, subjectId: ticket.observationID.uuidString.lowercased(), metadataJSON: "damaged other observation"))
        try context.save()
        #expect(try page(ticket, container).completed.isEmpty)
        var checks = 0
        #expect(throws: (any Error).self) {
            try Store.status(ownerID: ticket.ownerID, observationID: ticket.observationID, container: container,
                isCurrent: { checks += 1; return checks == 1 })
        }
        for limit in [0, 21] {
            #expect(throws: (any Error).self) { try Store.status(ownerID: ticket.ownerID, observationID: ticket.observationID,
                limit: limit, container: container, isCurrent: { true }) }
        }
        _ = try context.ensurePendingCloudDeletionTask(scanId: ticket.observationID.uuidString.lowercased(), requestingAccountID: ticket.ownerID)
        try context.save()
        #expect(throws: (any Error).self) { try page(ticket, container) }
    }
}
