import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized)
struct ObservationPublicationOperationStatusTests {
    let fixture = ObservationPublicationPersistenceTests()
    typealias Store = ObservationPublicationPersistence
    typealias Status = ObservationPublicationOperationStatus

    func read(_ container: ModelContainer, operation: UUID? = nil, analysis: UUID? = nil,
              owner: UUID? = nil, current: () -> Bool = { true }) throws -> Status? {
        try Status.read(operationID: operation ?? fixture.operation, ownerID: owner ?? fixture.owner,
                        observationID: fixture.observation, analysisID: analysis ?? fixture.analysis,
                        container: container, isCurrent: current)
    }
    func target(_ container: ModelContainer, owner: UUID? = nil, current: () -> Bool = { true }) throws -> Status? {
        try Status.readTarget(ownerID: owner ?? fixture.owner, observationID: fixture.observation,
                              container: container, isCurrent: current)
    }
    func stageAnother(_ container: ModelContainer, analysis: UUID? = nil) throws {
        _ = try Store.stage(fixture.request(operationID: UUID(), analysisID: analysis), ownerID: fixture.owner,
                            container: container, isCurrent: { true })
    }
    func job(_ context: ModelContext) throws -> OfflineJobRecord {
        try #require(try context.fetchOfflineJob(id: Store.jobID(fixture.operation, observationID: fixture.observation)))
    }
    func claim(_ intent: ObservationPublicationIntent, in container: ModelContainer) throws -> Store.Claim {
        try #require(try Store.claim(intent, at: fixture.now, container: container, isCurrent: { true }))
    }

    @Test func onlyExactAbsenceInsideValidScopeReturnsNil() throws {
        let container = try fixture.container()
        #expect(try read(container) == nil)
        #expect(try target(container) == nil)
        #expect(throws: (any Error).self) { try target(container, owner: UUID()) }
        #expect(throws: (any Error).self) { try target(container, current: { false }) }
        var targetChecks = 0
        #expect(throws: (any Error).self) { try target(container, current: { targetChecks += 1; return targetChecks == 1 }) }
        _ = try fixture.stage(container)
        #expect(try read(container, operation: UUID()) == nil)
        #expect(try target(container)?.operationID == fixture.operation)
        #expect(throws: (any Error).self) { try stageAnother(container) }
        #expect(throws: (any Error).self) { try read(container, owner: UUID()) }
        #expect(throws: (any Error).self) { try read(container, analysis: UUID()) }
        #expect(throws: (any Error).self) { try read(container, current: { false }) }
        var checks = 0
        #expect(throws: (any Error).self) { try read(container, current: { checks += 1; return checks == 1 }) }
    }

    @Test(arguments: ObservationPublicationStatus.allCases)
    func acknowledgedStatusesRemainHistoricalAndExact(_ status: ObservationPublicationStatus) throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        _ = try Store.acknowledge(fixture.receipt(status), expected: intent, at: fixture.now,
                                 container: container, isCurrent: { true })
        let terminal = status == .admitted || status == .needsAction
        #expect(throws: (any Error).self) { try stageAnother(container) }
        #expect(try target(container) == read(container))
        #expect(try fixture.stage(container).receipt?.status == status)
        #expect(try read(container)?.phase == (terminal ? .complete(status) : .reconciling))
        let jobs = try Store.candidates(container: container, ownerID: fixture.owner)
        #expect(jobs.count == (terminal ? 0 : 1))
        if !terminal {
            let saved = try Store.restore(job(ModelContext(container)))
            _ = try #require(try Store.claim(saved, at: fixture.now.addingTimeInterval(30), container: container, isCurrent: { true }))
        }
        #expect(try read(container)?.phase == (terminal ? .complete(status) : .reconciling))
    }

    @Test func realWriterPhasesAndHistoricalChildSurviveSelectionChange() throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        #expect(try read(container)?.phase == .pending)
        let first = try claim(intent, in: container)
        #expect(try read(container)?.phase == .pending)
        try Store.retry(first, at: fixture.now, needsAttention: false, container: container, isCurrent: { true })
        #expect(try read(container)?.phase == .pending)
        let next = try #require(try Store.claim(intent, at: fixture.now.addingTimeInterval(301), container: container, isCurrent: { true }))
        try Store.retry(next, at: fixture.now.addingTimeInterval(302), needsAttention: true, container: container, isCurrent: { true })
        let context = ModelContext(container)
        let scan = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        scan.selectedAnalysisID = UUID().uuidString.lowercased(); scan.observationStateRevision = (scan.observationStateRevision ?? 0) + 1
        try context.save()
        #expect(try read(container)?.phase == .needsAttention)
        #expect(try target(container)?.phase == .needsAttention)
        #expect(throws: (any Error).self) { try stageAnother(container) }
        #expect(try fixture.stage(container).identity.operationID == fixture.operation)
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).isEmpty)
        #expect(try Store.claim(intent, at: fixture.now.addingTimeInterval(999), container: container, isCurrent: { true }) == nil)
    }

    @Test(arguments: ["missing_deadline", "missing_start", "wrong_duration", "zero_attempt", "negative_attempt", "overflow_attempt",
                      "invalid_status", "pending_receipt", "waiting_missing_due", "waiting_without_attempt", "held_deadline", "bad_kind", "bad_subject", "bad_metadata"])
    func damagedShapeCannotDisplayOrClaimOrSchedule(_ damage: String) throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        _ = try claim(intent, in: container)
        let context = ModelContext(container), job = try job(context)
        switch damage {
        case "missing_deadline": job.nextRunAt = nil
        case "missing_start": job.lastAttemptAt = nil
        case "wrong_duration": job.nextRunAt = fixture.now.addingTimeInterval(179)
        case "zero_attempt": job.attemptCount = 0
        case "negative_attempt": job.attemptCount = -1
        case "overflow_attempt": job.attemptCount = Int.max
        case "invalid_status": job.statusRaw = "unknown"
        case "pending_receipt":
            let acknowledged = try intent.accepting(fixture.receipt(.accepted), at: fixture.now)
            job.metadataJSON = String(decoding: try acknowledged.storedData(), as: UTF8.self)
            job.status = .pending; job.attemptCount = 0; job.lastAttemptAt = nil; job.nextRunAt = nil
        case "waiting_missing_due": job.status = .waiting; job.nextRunAt = nil
        case "waiting_without_attempt": job.status = .waiting; job.attemptCount = 0; job.lastAttemptAt = nil
        case "held_deadline": job.status = .needsAttention
        case "bad_kind": job.kindRaw = "damaged"
        case "bad_subject": job.subjectId = UUID().uuidString.lowercased()
        default: job.metadataJSON = "{}"
        }
        try context.save()
        #expect(throws: (any Error).self) { try read(container) }
        #expect(throws: (any Error).self) { try target(container) }
        #expect(throws: (any Error).self) { try stageAnother(container) }
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).isEmpty)
        #expect(throws: (any Error).self) {
            try Store.claim(intent, at: fixture.now.addingTimeInterval(999), container: container, isCurrent: { true })
        }
    }

    @Test(arguments: ["parent", "parent_owner", "child", "child_owner", "child_parent", "job_owner"])
    func scopeDamageNeverLooksLikeAbsence(_ damage: String) throws {
        let container = try fixture.container(); _ = try fixture.stage(container)
        let context = ModelContext(container)
        let scan = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let child = try #require(try context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        switch damage {
        case "parent": context.delete(scan)
        case "parent_owner": scan.analysisOwnerAccountID = UUID().uuidString.lowercased()
        case "child": context.delete(child)
        case "child_owner", "child_parent":
            context.delete(child); try context.save()
            let replacement = try LocalAnalysisRecord(analysisID: fixture.analysis,
                observationID: damage == "child_parent" ? UUID().uuidString.lowercased() : scan.id,
                ownerAccountID: damage == "child_owner" ? UUID() : fixture.owner,
                completedAt: fixture.now, resultSnapshotData: Data("{}".utf8))
            context.insert(replacement); scan.analysisRecords = [replacement]
        default:
            let other = try ObservationPublicationIntent(request: fixture.request(), ownerID: UUID())
            let row = try job(context)
            row.metadataJSON = String(decoding: try other.storedData(), as: UTF8.self)
        }
        try context.save()
        #expect(throws: (any Error).self) { try read(container) }
        #expect(throws: (any Error).self) { try target(container) }
        #expect(throws: (any Error).self) { try stageAnother(container) }
    }

    @Test(arguments: [false, true])
    func exhaustedFinalClaimCannotScheduleButCanStillSettle(waiting: Bool) throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        let initial = try claim(intent, in: container)
        let context = ModelContext(container)
        let row = try job(context)
        row.attemptCount = Int.max - 2
        try context.save()
        let last = try #require(try Store.claim(intent, at: initial.expiresAt, container: container, isCurrent: { true }))
        #expect(last.attempt == Int.max - 1)
        try Store.requireDispatch(last, at: last.startedAt, container: container, isCurrent: { true })
        if waiting { try Store.retry(last, at: last.startedAt, needsAttention: false, container: container, isCurrent: { true }) }
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).isEmpty)
        #expect(try Store.claim(intent, at: last.expiresAt, container: container, isCurrent: { true }) == nil)
        #expect(try read(container)?.phase == .needsAttention)
        if !waiting {
            _ = try Store.acknowledge(fixture.receipt(.admitted), expected: intent, at: last.expiresAt.addingTimeInterval(1),
                                     container: container, isCurrent: { true }, claim: last)
            #expect(try read(container)?.phase == .complete(.admitted))
        }
    }

    @Test func discoveryPropagatesStorageFailureButSkipsDeniedScope() throws {
        let container = try fixture.container(); _ = try fixture.stage(container)
        let job = try job(ModelContext(container))
        #expect(throws: (any Error).self) {
            try Store.discover([job], ownerID: fixture.owner) { _ in throw CocoaError(.fileReadUnknown) }
        }
        #expect(try Store.discover([job], ownerID: fixture.owner) { _ in throw ObservationHistoryError.deleted }.isEmpty)
    }

    @Test func fractionalDatesPreserveClaimRecoveryAndRejectInvalidClock() throws {
        let container = try fixture.container(), intent = try fixture.stage(container)
        let now = fixture.now.addingTimeInterval(0.1234567)
        let first = try #require(try Store.claim(intent, at: now, container: container, isCurrent: { true }))
        #expect(try Store.candidates(container: container, ownerID: fixture.owner).first?.1 == first.expiresAt)
        #expect(try read(container)?.phase == .pending)
        #expect(try Store.claim(intent, at: now, container: container, isCurrent: { true }) == nil)
        #expect(throws: (any Error).self) { try Store.requireDispatch(first, at: now.addingTimeInterval(-1), container: container, isCurrent: { true }) }
        _ = try #require(try Store.claim(intent, at: first.expiresAt, container: container, isCurrent: { true }))
        #expect(throws: (any Error).self) {
            try Store.claim(intent, at: Date(timeIntervalSince1970: 32_503_680_001), container: container, isCurrent: { true })
        }
    }
    @Test func historicalTargetRemainsOriginalAfterAnotherChildIsSelected() throws {
        let container = try fixture.container(); _ = try fixture.stage(container)
        let context = ModelContext(container), other = UUID()
        let scan = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let child = try LocalAnalysisRecord(analysisID: other, observationID: scan.id,
            ownerAccountID: fixture.owner, completedAt: fixture.now, resultSnapshotData: Data("{}".utf8))
        context.insert(child); scan.analysisRecords?.append(child)
        scan.selectedAnalysisID = other.uuidString.lowercased(); try context.save()
        #expect(try target(container)?.analysisID == fixture.analysis)
        #expect(throws: (any Error).self) { try stageAnother(container, analysis: other) }
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test func legacyDuplicatesRequireExactRecoveryAndCannotAdmitAnother() throws {
        let container = try fixture.container(), original = try fixture.stage(container)
        let context = ModelContext(container)
        let legacy = try ObservationPublicationIntent(request: fixture.request(operationID: UUID()), ownerID: fixture.owner)
        context.insert(OfflineJobRecord(id: Store.jobID(legacy.identity.operationID, observationID: fixture.observation),
            kind: .observationPublicationSync, subjectId: fixture.observation.uuidString.lowercased(), priority: 65,
            metadataJSON: String(decoding: try legacy.storedData(), as: UTF8.self)))
        try context.save()
        #expect(throws: (any Error).self) { try target(container) }
        #expect(throws: (any Error).self) { try stageAnother(container) }
        #expect(try read(container)?.operationID == fixture.operation)
        #expect(try fixture.stage(container).storedData() == original.storedData())
    }

    @Test(arguments: [false, true])
    func damagedNamespaceWithMatchingSubjectCannotLookVacant(uppercase: Bool) throws {
        #expect(fixture.observation.uuidString.uppercased() != fixture.observation.uuidString.lowercased())
        let container = try fixture.container(), context = ModelContext(container)
        context.insert(OfflineJobRecord(id: "damaged-publication-key", kind: .observationPublicationSync,
            subjectId: uppercase ? fixture.observation.uuidString.uppercased() : fixture.observation.uuidString.lowercased(), priority: 65, metadataJSON: "{}"))
        try context.save()
        #expect(throws: (any Error).self) { try target(container) }
        #expect(throws: (any Error).self) { try fixture.stage(container) }
    }

}
