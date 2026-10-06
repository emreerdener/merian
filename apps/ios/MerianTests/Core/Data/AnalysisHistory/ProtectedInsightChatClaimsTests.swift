import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ProtectedInsightChatClaimsTests {
    typealias Store = ProtectedInsightChatPersistence
    let support = ProtectedInsightChatPersistenceTests()
    let start = Date(timeIntervalSince1970: 2_000)

    func seed() async throws -> (ModelContainer, ProtectedInsightChatIntent) {
        let (container, ticket) = try await support.seed()
        let request = try support.request(ticket, id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!)
        return (container, try Store.stage(request, ticket: ticket, container: container, isCurrent: { true }))
    }
    func claim(_ intent: ProtectedInsightChatIntent, in container: ModelContainer) throws -> Store.Claim {
        let value = try Store.claimInitial(intent, at: start, container: container, isCurrent: { true })
        return try #require(value)
    }
    func receipt(_ intent: ProtectedInsightChatIntent, text: String = "Synthetic answer") throws -> Data {
        let request = intent.request
        let message: [String: Any] = ["id": "9ef24f67-5a9f-8221-b079-90542bb746f9",
            "conversation_id": request.conversationID.uuidString.lowercased(), "scan_id": request.observationID.uuidString.lowercased(),
            "client_message_id": request.clientMessageID.uuidString.lowercased(), "role": "assistant", "text": text,
            "model": "gemini-2.5-flash", "is_refusal": false, "refusal_reason": NSNull(), "created_at": "2026-10-06T12:00:00Z"]
        return try JSONSerialization.data(withJSONObject: ["data": ["context_version": 1, "completed": true, "message": message]])
    }
    func proof(_ intent: ProtectedInsightChatIntent) throws -> Data {
        let request = intent.request
        return try JSONSerialization.data(withJSONObject: ["data": ["context_version": 1, "outcome": "not_admitted",
            "scan_id": request.observationID.uuidString.lowercased(), "conversation_id": request.conversationID.uuidString.lowercased(),
            "client_message_id": request.clientMessageID.uuidString.lowercased(), "reason": "displayed_identification_changed"]])
    }

    func job(_ intent: ProtectedInsightChatIntent, in context: ModelContext) throws -> OfflineJobRecord {
        let value = try context.fetchOfflineJob(id: Store.jobID(intent.request))
        return try #require(value)
    }

    @Test func oneInitialClaimAndExplicitReplayRetainExactRequest() async throws {
        let (container, intent) = try await seed(), first = try claim(intent, in: container)
        #expect(first.attempt == 1)
        #expect(try Store.claimInitial(intent, at: start, container: container, isCurrent: { true }) == nil)
        #expect(try Store.claimExplicitReplay(first, at: start, container: container, isCurrent: { true }) == nil)
        try Store.requireDispatch(first, at: start.addingTimeInterval(1), container: container, isCurrent: { true })
        try Store.hold(first, at: start.addingTimeInterval(2), container: container, isCurrent: { true })
        try Store.hold(first, at: start.addingTimeInterval(3), container: container, isCurrent: { true })
        let context = ModelContext(container), held = try job(intent, in: context)
        #expect(held.status == .needsAttention && held.nextRunAt == nil)
        #expect(try Store.claimInitial(intent, at: start.addingTimeInterval(5), container: container, isCurrent: { true }) == nil)
        let recovery = try Store.currentAttempt(intent, container: container, isCurrent: { true })
        let prior = try #require(recovery)
        let replay = try Store.claimExplicitReplay(prior, at: start.addingTimeInterval(5), container: container, isCurrent: { true })
        let second = try #require(replay)
        #expect(second.attempt == 2 && second.intent.request == intent.request)
        #expect(try second.intent.storedData() == intent.storedData())
        #expect(throws: (any Error).self) { try Store.claimExplicitReplay(first, at: start.addingTimeInterval(6), container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.requireDispatch(first, at: start.addingTimeInterval(6), container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.acknowledge(receipt(intent), claim: first, at: start.addingTimeInterval(6), container: container, isCurrent: { true }) }
    }

    @Test func expiryClosesDispatchButAcceptsExactLateReply() async throws {
        let (container, intent) = try await seed(), first = try claim(intent, in: container)
        #expect(throws: (any Error).self) { try Store.requireDispatch(first, at: first.expiresAt, container: container, isCurrent: { true }) }
        let date = first.expiresAt.addingTimeInterval(5)
        let completed = try Store.acknowledge(receipt(intent), claim: first, at: date, container: container, isCurrent: { true })
        #expect(completed.isComplete && completed.observedAt == date)
        #expect(try Store.acknowledge(receipt(intent), claim: first, at: date.addingTimeInterval(1), container: container, isCurrent: { true }).observedAt == date)
        #expect(throws: (any Error).self) { try Store.acknowledge(receipt(intent, text: "Changed"), claim: first, at: date, container: container, isCurrent: { true }) }
        #expect(try Store.claimInitial(intent, at: date, container: container, isCurrent: { true }) == nil)
        #expect(try Store.claimExplicitReplay(first, at: date, container: container, isCurrent: { true }) == nil)
        #expect(try Store.currentAttempt(intent, container: container, isCurrent: { true }) == nil)
        #expect(throws: (any Error).self) { try Store.hold(first, at: date, container: container, isCurrent: { true }) }
        let scan = try ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: ModelContext(container))
        #expect(scan.observationStateRevision == 10 && scan.selectedAnalysisID == intent.request.selection.analysisID.uuidString.lowercased())
    }

    @Test func expiredOrphanNeedsExplicitReplayAndOldReplyCannotWin() async throws {
        let (container, intent) = try await seed(), first = try claim(intent, in: container)
        let date = first.expiresAt
        #expect(try Store.claimInitial(intent, at: date, container: container, isCurrent: { true }) == nil)
        let replay = try Store.claimExplicitReplay(first, at: date, container: container, isCurrent: { true })
        let second = try #require(replay)
        #expect(throws: (any Error).self) { try Store.acknowledge(receipt(intent), claim: first, at: date, container: container, isCurrent: { true }) }
        #expect(try Store.acknowledge(receipt(intent), claim: second, at: date, container: container, isCurrent: { true }).isComplete)
    }

    @Test(arguments: ["parent", "child", "owner", "tombstone", "metadata"])
    func changedScopeCannotDispatchOrAcknowledge(change: String) async throws {
        let (container, intent) = try await seed(), first = try claim(intent, in: container)
        try support.source.update(container) { scan, context in
            switch change {
            case "parent": context.delete(scan)
            case "child": for child in try context.fetch(FetchDescriptor<LocalAnalysisRecord>()) { context.delete(child) }
            case "owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
            case "tombstone": _ = try context.ensurePendingCloudDeletionTask(scanId: scan.id, requestingAccountID: intent.ownerID)
            default: try job(intent, in: context).metadataJSON = "damaged"
            }
        }
        #expect(throws: (any Error).self) { try Store.requireDispatch(first, at: start, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.acknowledge(receipt(intent), claim: first, at: start, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.hold(first, at: start, container: container, isCurrent: { true }) }
    }

    @Test func transactionFailureRollsBackEveryPhase() async throws {
        let (container, intent) = try await seed()
        #expect(throws: (any Error).self) {
            try Store.claimInitial(intent, at: start, container: container, isCurrent: { true }, save: { _ in throw Store.IntegrityError.unavailable })
        }
        #expect(try job(intent, in: ModelContext(container)).status == .pending)
        var checks = 0
        #expect(throws: (any Error).self) {
            try Store.claimInitial(intent, at: start, container: container, isCurrent: { checks += 1; return checks == 1 })
        }
        let first = try claim(intent, in: container)
        #expect(throws: (any Error).self) {
            try Store.hold(first, at: start, container: container, isCurrent: { true }, save: { _ in throw Store.IntegrityError.unavailable })
        }
        #expect(throws: (any Error).self) {
            try Store.acknowledge(receipt(intent), claim: first, at: start, container: container, isCurrent: { true }, save: { _ in throw Store.IntegrityError.unavailable })
        }
        #expect(try job(intent, in: ModelContext(container)).status == .running)
        #expect(throws: (any Error).self) { try Store.requireDispatch(first, at: start, container: container, isCurrent: { false }) }
        #expect(throws: (any Error).self) { try Store.acknowledge(receipt(intent), claim: first, at: start, container: container, isCurrent: { false }) }
    }

    @Test(arguments: ["missingExpiry", "wrongExpiry", "zeroAttempt", "badStart", "waiting", "heldDeadline", "heldCode"])
    func malformedExecutionNeverBecomesAuthority(change: String) async throws {
        let (container, intent) = try await seed(), first = try claim(intent, in: container)
        let context = ModelContext(container), row = try job(intent, in: context)
        switch change {
        case "missingExpiry": row.nextRunAt = nil
        case "wrongExpiry": row.nextRunAt = start.addingTimeInterval(1)
        case "zeroAttempt": row.attemptCount = 0
        case "badStart": row.lastAttemptAt = nil
        case "waiting": row.status = .waiting
        case "heldDeadline": row.status = .needsAttention; row.lastErrorCode = Store.heldCode
        default: row.status = .needsAttention; row.nextRunAt = nil
        }
        try context.save()
        #expect(throws: (any Error).self) { try Store.restore(row) }
        #expect(throws: (any Error).self) { try Store.currentAttempt(intent, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.claimExplicitReplay(first, at: first.expiresAt, container: container, isCurrent: { true }) }
    }

    @Test func cancellationHoldsWithoutAutomaticRestart() async throws {
        let (container, intent) = try await seed(), first = try claim(intent, in: container)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try Store.hold(first, at: start, container: container, isCurrent: { true })
        }
        try await task.value
        let current = try job(intent, in: ModelContext(container))
        #expect(current.status == .needsAttention && current.nextRunAt == nil && current.attemptCount == 1)
        #expect(try Store.claimInitial(intent, at: first.expiresAt, container: container, isCurrent: { true }) == nil)
    }

    @Test(arguments: [false, true])
    func diskRestartRestoresHeldGenerationOrExactProofWithoutDispatchPermission(terminal: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema(CurrentSchema.models), url = root.appendingPathComponent("store.sqlite")
        func open() throws -> ModelContainer { try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]) }
        do {
            let container = try open(), context = ModelContext(container)
            let scan = LocalScanRecord(id: support.source.support.observation, speciesId: "", scientificName: "Synthetic source", commonName: "Synthetic source")
            scan.analysisOwnerAccountID = support.source.support.owner.uuidString.lowercased()
            scan.observationStateRevision = 10; scan.selectedAnalysisID = support.source.analysisID
            context.insert(scan); try context.save()
            _ = try await support.source.service(data: support.source.fixture(revision: 10))
                .syncSelected(observationID: scan.id, container: container)
            let current = ModelContext(container), parent = try ObservationHistorySyncService.enrolledScan(scan.id, context: current)
            let entry = try ObservationHistoryListingService.entry(UUID(uuidString: support.source.analysisID)!, scan: parent, context: current)
            let ticket = try ProtectedInsightChatTicket(entry: entry, context: .init(owner: support.source.support.owner,
                selected: entry.result.analysisID, revision: 10, pendingOperation: nil, undoOperation: nil), observationID: UUID(uuidString: scan.id)!)
            let intent = try Store.stage(support.request(ticket), ticket: ticket, container: container, isCurrent: { true })
            let attempt = try claim(intent, in: container)
            if terminal {
                _ = try Store.acknowledge(proof(intent), claim: attempt, at: start, container: container, isCurrent: { true })
            } else { try Store.hold(attempt, at: start, container: container, isCurrent: { true }) }
        }
        let container = try open(), context = ModelContext(container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let intent = try Store.restore(row)
        let page = try Store.status(ownerID: intent.ownerID, observationID: intent.request.observationID,
            container: container, isCurrent: { true })
        if terminal {
            #expect(page.unfinished == nil && page.completed.first?.receiptKind == .notAdmitted)
            #expect(try page.completed.first?.storedData() == intent.storedData())
            let parent = try ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: context)
            let entry = try ObservationHistoryListingService.entry(intent.request.selection.analysisID, scan: parent, context: context)
            let ticket = try ProtectedInsightChatTicket(entry: entry, context: .init(owner: intent.ownerID,
                selected: intent.request.selection.analysisID, revision: 10, pendingOperation: nil, undoOperation: nil),
                observationID: intent.request.observationID)
            #expect(try Store.stage(intent.request, ticket: ticket, container: container, isCurrent: { true }).storedData() == intent.storedData())
            #expect(throws: Store.IntegrityError.identificationRefreshRequired) {
                try Store.stage(support.request(ticket), ticket: ticket, container: container, isCurrent: { true })
            }
            #expect(try Store.status(ownerID: intent.ownerID, observationID: intent.request.observationID,
                displayedSelection: ticket.selection, container: container, isCurrent: { true }).requiresIdentificationRefresh)
            #expect(try Store.currentAttempt(intent, container: container, isCurrent: { true }) == nil)
            return
        }
        #expect(page.unfinished?.state == .held && page.completed.isEmpty)
        #expect(try page.unfinished?.intent.storedData() == intent.storedData())
        let recovered = try Store.currentAttempt(intent, container: container, isCurrent: { true })
        let previous = try #require(recovered)
        #expect(previous.attempt == 1 && previous.startedAt == start && previous.intent.request == intent.request)
        #expect(throws: (any Error).self) { try Store.requireDispatch(previous, at: start, container: container, isCurrent: { true }) }
        let replay = try Store.claimExplicitReplay(previous, at: start.addingTimeInterval(1), container: container, isCurrent: { true })
        #expect(replay?.attempt == 2 && replay?.intent.request == intent.request)
    }
    @Test func terminalProofSettlesLateAtomicallyAndRetiresOnlyItsOwnClaim() async throws {
        let (container, intent) = try await seed(), claim = try claim(intent, in: container)
        let proof = try proof(intent), late = claim.expiresAt.addingTimeInterval(5)
        #expect(throws: (any Error).self) {
            try Store.acknowledge(proof, claim: claim, at: late, container: container, isCurrent: { true }, save: { _ in throw Store.IntegrityError.unavailable })
        }
        #expect(try job(intent, in: ModelContext(container)).status == .running)
        let completed = try Store.acknowledge(proof, claim: claim, at: late, container: container, isCurrent: { true })
        #expect(completed.receiptKind == .notAdmitted && completed.observedAt == late)
        #expect(try Store.acknowledge(proof, claim: claim, at: late.addingTimeInterval(1), container: container, isCurrent: { true }).storedData() == completed.storedData())
        #expect(try Store.claimInitial(intent, at: late, container: container, isCurrent: { true }) == nil)
        #expect(throws: (any Error).self) { try Store.acknowledge(receipt(intent), claim: claim, at: late, container: container, isCurrent: { true }) }
        let parent = try ObservationHistorySyncService.enrolledScan(intent.request.observationID.uuidString, context: ModelContext(container))
        #expect(parent.observationStateRevision == 10)
    }

    @Test(arguments: ["held", "replaced", "account", "deletion"])
    func proofCannotReleaseChangedClaimOrScope(change: String) async throws {
        let (container, intent) = try await seed(), first = try claim(intent, in: container)
        if change == "held" || change == "replaced" {
            try Store.hold(first, at: start, container: container, isCurrent: { true })
            if change == "replaced" { _ = try Store.claimExplicitReplay(first, at: start.addingTimeInterval(1), container: container, isCurrent: { true }) }
        } else if change == "deletion" {
            try support.source.update(container) { scan, context in
                _ = try context.ensurePendingCloudDeletionTask(scanId: scan.id, requestingAccountID: intent.ownerID)
            }
        }
        #expect(throws: (any Error).self) {
            try Store.acknowledge(proof(intent), claim: first, at: start.addingTimeInterval(2), container: container, isCurrent: { change != "account" })
        }
    }

}
