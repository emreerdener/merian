import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisExecutionTests {
    typealias Store = ObservationReanalysisExecutionStore
    let fixture = ObservationReanalysisPersistenceTests()
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    func claim(_ container: ModelContainer) throws -> Store.Claim {
        _ = try fixture.stage(container)
        let intent = try fixture.intent()
        let snapshot = try Store.bindAndAdmit(.init(identity: intent.identity, evidence: intent.request.evidence),
            processor: intent.request.processor, now: now, container: container, isCurrent: { true })
        return try Store.claim(snapshot, admission: .initial, now: now, container: container, isCurrent: { true })
    }

    func result() throws -> Data {
        let request = try fixture.intent().request
        var (_, snapshot) = try ObservationReanalysisResultTests().fixture()
        let input = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        for key in ["observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest"] { snapshot[key] = input[key] }
        var identification = try #require(snapshot["result"] as? [String: Any])
        identification["scan_id"] = request.observationID.uuidString.lowercased(); snapshot["result"] = identification
        return try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
    }

    @Test func dueRetryAdvancesFenceAndNeverChangesRequest() throws {
        let container = try fixture.fixture.container(), first = try claim(container)
        #expect(first.snapshot.attempt == 1 && first.snapshot.status == .running)
        try Store.settle(first, as: .waiting(until: now.addingTimeInterval(30), server: nil), now: now,
            container: container, isCurrent: { true })
        let waiting = try Store.read(first.intent.identity, container: container, isCurrent: { true })
        #expect(throws: (any Error).self) {
            try Store.claim(waiting, admission: .dueRetry, now: now, container: container, isCurrent: { true })
        }
        let second = try Store.claim(waiting, admission: .dueRetry, now: now.addingTimeInterval(30), container: container, isCurrent: { true })
        #expect(second.snapshot.attempt == 2 && second.intent == first.intent)
        #expect(throws: (any Error).self) { try Store.validate(first, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.settle(first, as: .held(.terminalFailure), now: now, container: container, isCurrent: { true })
        }
        #expect(throws: (any Error).self) { try Store.complete(first, resultBytes: result(), container: container, isCurrent: { true }) }
        try Store.validate(second, container: container, isCurrent: { true })
    }

    @Test func interruptedClaimFencesOlderWorkerEvenAtSameTimestamp() throws {
        let container = try fixture.fixture.container(), first = try claim(container)
        let second = try Store.claim(first.snapshot, admission: .interrupted, now: now, container: container, isCurrent: { true })
        #expect(second.snapshot.attempt == 2 && second.snapshot.lastAttempt == first.snapshot.lastAttempt)
        #expect(throws: (any Error).self) { try Store.validate(first, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.claim(first.snapshot, admission: .interrupted, now: now, container: container, isCurrent: { true })
        }
        try Store.validate(second, container: container, isCurrent: { true })
    }

    @Test(arguments: [Store.Hold.evidenceUnavailable, .consentRequired, .terminalFailure, .reconciliationRequired, .retryLimit])
    func remediationRetainsExactRequestAndCannotAutomaticallyRevive(_ reason: Store.Hold) throws {
        let container = try fixture.fixture.container(), first = try claim(container)
        try Store.settle(first, as: .held(reason), now: now, container: container, isCurrent: { true })
        let held = try Store.read(first.intent.identity, container: container, isCurrent: { true })
        #expect(held.hold == reason && held.intent == first.intent && held.nextRun == nil)
        if reason == .terminalFailure { #expect(held.server == .failedTerminal) }
        for admission in [Store.Admission.initial, .dueRetry, .interrupted] {
            #expect(throws: (any Error).self) { try Store.claim(held, admission: admission, now: now, container: container, isCurrent: { true }) }
        }
        let (_, row, _) = try fixture.stored(container)
        #expect(row.inferenceImagePaths == first.intent.photoPaths && row.queueNeedsAttention)
    }

    @Test func completionAppendsAndRetiresOnlyTransportWithoutChangingSelection() throws {
        let container = try fixture.fixture.container(), active = try claim(container), bytes = try result()
        let receipt = try Store.complete(active, resultBytes: bytes, container: container, isCurrent: { true })
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == fixture.fixture.analysis.uuidString.lowercased())
        #expect(parent.observationStateRevision == 3 && parent.isBiological == false)
        #expect(parent.analysisRecords?.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: fixture.child.uuidString.lowercased())) == nil)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        #expect(try ObservationReanalysisErasurePersistence.validate(receipt, container: container, isCurrent: { true }, complete: true))
        #expect(try Store.complete(active, resultBytes: bytes, container: container, isCurrent: { true }) == receipt)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
        #expect(throws: (any Error).self) { try fixture.stage(container) }
    }

    @Test(arguments: [false, true])
    func completionFailureRollsBackAppendRetirementAndErasure(accountChange: Bool) throws {
        let container = try fixture.fixture.container(), active = try claim(container)
        var checks = 0
        #expect(throws: (any Error).self) {
            try Store.complete(active, resultBytes: result(), container: container,
                isCurrent: { checks += 1; return !accountChange || checks < 3 },
                save: { _ in throw CocoaError(.fileWriteUnknown) })
        }
        let context = ModelContext(container)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        try Store.validate(active, container: container, isCurrent: { true })
    }

    @Test(arguments: ["owner", "source", "deletion", "metadata", "counter", "hold", "server", "row-error", "timestamp", "child-deletion", "child-scan"])
    func changesAfterClaimDenyStaleCompletion(_ change: String) throws {
        let container = try fixture.fixture.container(), active = try claim(container)
        let (context, row, job) = try fixture.stored(container)
        switch change {
        case "owner": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        case "source": context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first))
        case "deletion": context.insert(PendingCloudDeletionTask(scanId: fixture.fixture.observation.uuidString.lowercased()))
        case "metadata": job.metadataJSON = try #require(String(bytes: fixture.intent(text: "Changed").storedData(), encoding: .utf8))
        case "counter": row.queueAttemptCount += 1
        case "timestamp": row.queueUpdatedAt = now.addingTimeInterval(1)
        case "child-deletion": context.insert(PendingCloudDeletionTask(scanId: fixture.child.uuidString))
        case "child-scan": context.insert(LocalScanRecord(id: fixture.child.uuidString, speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture"))
        case "hold": job.lastErrorCode = "future-reason"; row.queueLastErrorCode = "future-reason"
        case "server": job.serverStatus = "future-status"; row.queueLastServerStatus = "future-status"
        default: row.queueLastErrorMessage = "unexpected diagnostic"
        }
        try context.save()
        #expect(throws: (any Error).self) { try Store.complete(active, resultBytes: result(), container: container, isCurrent: { true }) }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try ModelContext(container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(fixture.child)) == nil)
    }

    @Test func completedReplayStillRequiresSameBytesOwnerAndLivingParent() throws {
        let container = try fixture.fixture.container(), active = try claim(container), bytes = try result()
        _ = try Store.complete(active, resultBytes: bytes, container: container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.complete(active, resultBytes: bytes, container: container, isCurrent: { false }) }
        var changed = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        changed["ordinal"] = 50
        #expect(throws: (any Error).self) {
            try Store.complete(active, resultBytes: JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys]),
                container: container, isCurrent: { true })
        }
        let context = ModelContext(container)
        context.insert(PendingCloudDeletionTask(scanId: fixture.fixture.observation.uuidString.lowercased())); try context.save()
        #expect(throws: (any Error).self) { try Store.complete(active, resultBytes: bytes, container: container, isCurrent: { true }) }
    }

    @Test func historySyncMayAdmitTheExactResultBeforeQueueRetirement() throws {
        let container = try fixture.fixture.container(), active = try claim(container), bytes = try result()
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let result = try ObservationReanalysisResult.decode(bytes, matching: active.intent.request)
        _ = try ObservationHistorySyncService.insert([result], into: parent, ownerID: active.intent.ownerID, context: context)
        try context.save()
        _ = try Store.complete(active, resultBytes: bytes, container: container, isCurrent: { true })
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: ["receipt", "job"])
    func uppercaseAliasesCannotSplitExecutionOrErasureOwnership(_ alias: String) throws {
        let original = try fixture.intent(), container = try fixture.fixture.container()
        let child = try #require(UUID(uuidString: "abcdefab-abcd-4abc-8abc-abcdefabcdef"))
        let intent = try ObservationReanalysisIntent(ownerID: original.ownerID, request: .init(
            observationID: original.request.observationID, analysisID: child, sourceAnalysisID: original.request.sourceAnalysisID,
            processor: original.request.processor, evidence: original.request.evidence))
        _ = try ObservationReanalysisPersistence.stage(intent, container: container, isCurrent: { true })
        let snapshot = try Store.bindAndAdmit(.init(identity: intent.identity, evidence: intent.request.evidence),
            processor: intent.request.processor, now: now, container: container, isCurrent: { true })
        let active = try Store.claim(snapshot, admission: .initial, now: now, container: container, isCurrent: { true })
        let context = ModelContext(container)
        if alias == "receipt" {
            context.insert(OfflineJobRecord(id: "reanalysis-erasure:" + child.uuidString, kind: .observationReanalysisErasure))
        } else {
            context.insert(OfflineJobRecord(id: OfflineQueueManager.scanIngestionJobId(scanId: child.uuidString), kind: .observationReanalysisSync))
        }
        try context.save()
        #expect(throws: (any Error).self) { try Store.validate(active, container: container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try Store.read(intent.identity, container: container, isCurrent: { true }) }
    }

    @Test(arguments: [false, true])
    func uppercaseErasureReceiptAlsoBlocksInitialStaging(bound: Bool) throws {
        let original = try fixture.intent(), container = try fixture.fixture.container()
        let child = try #require(UUID(uuidString: "abcdefab-abcd-4abc-8abc-abcdefabcdef"))
        let intent = try ObservationReanalysisIntent(ownerID: original.ownerID, request: .init(
            observationID: original.request.observationID, analysisID: child, sourceAnalysisID: original.request.sourceAnalysisID,
            processor: original.request.processor, evidence: original.request.evidence))
        let context = ModelContext(container)
        context.insert(OfflineJobRecord(id: "reanalysis-erasure:" + child.uuidString, kind: .observationReanalysisErasure))
        try context.save()
        #expect(throws: (any Error).self) {
            if bound {
                _ = try ObservationReanalysisPersistence.stage(intent, container: container, isCurrent: { true })
            } else {
                _ = try ObservationReanalysisPersistence.stageDraft(.init(identity: intent.identity, evidence: intent.request.evidence),
                    container: container, isCurrent: { true })
            }
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test func restartRetainsAttemptFenceAndExactImmutableRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let first: Store.Claim
        do { let container = try fixture.fixture.container(url: url); first = try claim(container) }
        let reopened = try fixture.fixture.container(url: url, seed: false)
        let snapshot = try Store.read(first.intent.identity, container: reopened, isCurrent: { true })
        #expect(snapshot == first.snapshot)
        let replacement = try Store.claim(snapshot, admission: .interrupted, now: now, container: reopened, isCurrent: { true })
        #expect(replacement.snapshot.attempt == 2 && replacement.intent == first.intent)
        #expect(throws: (any Error).self) { try Store.validate(first, container: reopened, isCurrent: { true }) }
    }
}
