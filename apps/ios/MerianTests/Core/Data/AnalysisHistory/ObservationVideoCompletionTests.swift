import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoCompletionTests {
    typealias Store = ObservationVideoExecutionStore
    typealias Seed = ObservationVideoDurabilityTests.Seed

    func result(_ request: ObservationVideoReanalysisRequest) throws -> Data {
        var row = try ObservationHistorySyncTests().videoSnapshot()
        row["observation_id"] = request.observationID.uuidString.lowercased()
        row["analysis_id"] = request.analysisID.uuidString.lowercased()
        row["source_analysis_id"] = request.sourceAnalysisID.uuidString.lowercased()
        row["request_digest"] = request.requestDigest
        row["evidence_manifest"] = try JSONSerialization.jsonObject(with: request.manifest.originalBytes)
        row["ordinal"] = 2
        var identification = try #require(row["result"] as? [String: Any])
        identification["scan_id"] = request.observationID.uuidString.lowercased()
        row["result"] = identification
        return try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    func consumed(audio: Bool = true) async throws -> (Seed, Store.Snapshot) {
        let helper = ObservationVideoExecutionStoreTests()
        let (seed, upload) = try await helper.ready(audio: audio)
        do {
            let claim = try Store.claim(helper.stage(seed, upload), proof: seed.proof, container: seed.container, isCurrent: { true })
            let permit = try Store.consume(claim, proof: seed.proof, authorization: helper.authorization,
                container: seed.container, isCurrent: { true })
            return (seed, permit.snapshot)
        } catch { seed.remove(); throw error }
    }

    func assertCompleted(_ seed: Seed, bytes: Data, container: ModelContainer) throws {
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
        #expect(parent.observationStateRevision == 10)
        let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.id == seed.source.analysisID.uuidString.lowercased() }?.resultSnapshotData == seed.source.snapshot)
        let child = try #require(records.first { $0.id == seed.preparation.identity.analysisID.uuidString.lowercased() })
        #expect(child.resultSnapshotData == bytes && child.snapshotVersion == 5 && child.state == nil)
        #expect(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).isEmpty)
        #expect(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: child.id)) == nil)
        let cleanup = try #require(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.preparation.identity.analysisID)))
        #expect(try ObservationReanalysisErasureReceipt.restore(cleanup) == .init(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID))
        for file in seed.preparation.files { #expect(FileManager.default.fileExists(atPath: seed.root.appendingPathComponent(file.path).path)) }
    }

    @Test(arguments: [false, true], [false, true])
    func receivedResultSettlesCancelledRunningOrHeldWork(audio: Bool, held: Bool) async throws {
        let (seed, running) = try await consumed(audio: audio); defer { seed.remove() }
        let saved = try held ? Store.hold(running, proof: seed.proof, container: seed.container, isCurrent: { true }) : running
        let bytes = try result(saved.work.request), proof = try seed.proof
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Store.complete(saved, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true })
        }
        let receipt = try await task.value
        try assertCompleted(seed, bytes: bytes, container: seed.container)
        #expect(try Store.complete(saved, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true },
            save: { _ in Issue.record("Exact replay must not save") }) == receipt)
        #expect(throws: (any Error).self) { try Store.read(proof: proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) {
            try Store.complete(saved, resultBytes: bytes + Data(" ".utf8), proof: proof, container: seed.container, isCurrent: { true })
        }
    }

    @Test(arguments: [false, true])
    func uncertainSaveReopensWithOnlySettlementOrReceipt(committed: Bool) async throws {
        let (seed, saved) = try await consumed(); defer { seed.remove() }
        let bytes = try result(saved.work.request), proof = try seed.proof
        #expect(throws: (any Error).self) {
            try Store.complete(saved, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }, save: { context in
                if committed { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == (committed ? 2 : 1))
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (committed ? 0 : 1))
        #expect(throws: (any Error).self) { try Store.complete(saved, resultBytes: bytes, proof: proof, container: reopened, isCurrent: { true }) }
        if committed {
            #expect(throws: (any Error).self) { try Store.read(proof: proof, container: reopened, isCurrent: { true }) }
            // Same-container retry proves save-then-throw idempotence; reopened receipt owns cleanup.
            _ = try Store.complete(saved, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true })
        } else {
            let recovered = try Store.read(proof: proof, container: reopened, isCurrent: { true })
            #expect(recovered.work.consumed && recovered.work.request.body == saved.work.request.body)
            #expect(throws: (any Error).self) { try Store.claim(recovered, proof: proof, container: reopened, isCurrent: { true }) }
            _ = try Store.complete(recovered, resultBytes: bytes, proof: proof, container: reopened, isCurrent: { true })
        }
        try assertCompleted(seed, bytes: bytes, container: reopened)
    }

    @Test func unconsumedAndStaleSnapshotsCannotComplete() async throws {
        let helper = ObservationVideoExecutionStoreTests()
        let (seed, upload) = try await helper.ready(); defer { seed.remove() }
        let idle = try helper.stage(seed, upload), bytes = try result(idle.work.request), proof = try seed.proof
        #expect(throws: (any Error).self) { try Store.complete(idle, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }) }
        let claim = try Store.claim(idle, proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.complete(claim.snapshot, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }) }
        let permit = try Store.consume(claim, proof: proof, authorization: helper.authorization, container: seed.container, isCurrent: { true })
        let held = try Store.hold(permit.snapshot, proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.complete(permit.snapshot, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }) }
        _ = try Store.complete(held, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true })
    }

    @Test(arguments: ["account", "account-before-save", "source", "erasure", "row", "job", "child-namespace", "receipt", "result"])
    func changedScopeCannotAppendOrRetire(reason: String) async throws {
        let (seed, saved) = try await consumed(); defer { seed.remove() }
        let bytes = try result(saved.work.request), proof = try seed.proof
        let context = ModelContext(seed.container)
        if reason == "source" { context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)) }
        if reason == "erasure" { _ = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString.lowercased(), context: context) }
        if reason == "row" { try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).queueAttemptCount = 1 }
        if reason == "job" { try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: seed.preparation.identity.analysisID.uuidString.lowercased()))).metadataJSON = "{}" }
        if reason == "child-namespace" { context.insert(LocalScanRecord(id: seed.preparation.identity.analysisID.uuidString.lowercased(), speciesId: "synthetic", scientificName: "Synthetic", commonName: "Synthetic")) }
        if reason == "receipt" { try ObservationReanalysisErasureReceipt(parentID: UUID(), childID: seed.preparation.identity.analysisID).record(in: context) }
        try context.save()
        var checks = 0
        #expect(throws: (any Error).self) {
            try Store.complete(saved, resultBytes: reason == "result" ? Data("{}".utf8) : bytes, proof: proof,
                container: seed.container, isCurrent: {
                    checks += 1
                    return reason != "account" && (reason != "account-before-save" || checks == 1)
                })
        }
        #expect(try ModelContext(seed.container).fetch(FetchDescriptor<LocalAnalysisRecord>()).allSatisfy { $0.id != seed.preparation.identity.analysisID.uuidString.lowercased() })
        if reason != "erasure" { #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1) }
    }

    @Test(arguments: ["none", "time", "bytes"])
    func syncedResultMustBeByteIdentical(conflict: String) async throws {
        let (seed, saved) = try await consumed(); defer { seed.remove() }
        let bytes = try result(saved.work.request), proof = try seed.proof
        var row = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        if conflict == "time" { row["completed_at_ms"] = 1750000000001 }
        let stored = conflict == "time" ? try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) : bytes + (conflict == "bytes" ? Data(" ".utf8) : Data())
        let decoded = try ObservationReanalysisResult.decode(stored, matching: saved.work.request)
        let context = ModelContext(seed.container)
        let parent = try ObservationHistorySyncService.enrolledScan(seed.source.observationID.uuidString, context: context)
        _ = try ObservationHistorySyncService.insert([decoded], into: parent, ownerID: seed.source.ownerID, context: context)
        try context.save()
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(throws: (any Error).self) { try Store.read(proof: proof, container: reopened, isCurrent: { true }) }
        let recovered = try Store.readSyncedForSettlement(proof: proof, container: reopened, isCurrent: { true })
        #expect(recovered.work == saved.work)
        #expect(throws: (any Error).self) { try Store.claim(recovered, proof: proof, container: reopened, isCurrent: { true }) }
        if conflict != "none" {
            #expect(throws: (any Error).self) { try Store.complete(recovered, resultBytes: bytes, proof: proof, container: reopened, isCurrent: { true }) }
            #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        } else {
            _ = try Store.complete(recovered, resultBytes: bytes, proof: proof, container: reopened, isCurrent: { true })
            try assertCompleted(seed, bytes: bytes, container: reopened)
        }
    }

    @Test(arguments: ["absent", "owner", "parent", "version", "time", "bytes", "account", "source", "row", "metadata", "unconsumed", "idle", "receipt"])
    func syncedSettlementReaderRejectsUnprovenOrChangedWork(reason: String) async throws {
        let (seed, saved) = try await consumed(); defer { seed.remove() }
        let bytes = try result(saved.work.request), proof = try seed.proof
        let context = ModelContext(seed.container)
        let parent = try ObservationHistorySyncService.enrolledScan(seed.source.observationID.uuidString, context: context)
        if reason != "absent" {
            let result = try ObservationReanalysisResult.decode(bytes, matching: saved.work.request)
            let child = try LocalAnalysisRecord(analysisID: seed.preparation.identity.analysisID,
                observationID: reason == "parent" ? UUID().uuidString.lowercased() : parent.id,
                ownerAccountID: reason == "owner" ? UUID() : seed.source.ownerID,
                completedAt: reason == "time" ? .distantPast : result.completedAt,
                snapshotVersion: reason == "version" ? 4 : result.version,
                resultSnapshotData: reason == "bytes" ? Data("{}".utf8) : bytes)
            context.insert(child); parent.analysisRecords?.append(child)
        }
        if reason == "source" { context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first { $0.id == seed.source.analysisID.uuidString.lowercased() })) }
        if reason == "row" { try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first).queueAttemptCount = 1 }
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: seed.preparation.identity.analysisID.uuidString.lowercased())))
        if reason == "metadata" { job.metadataJSON = "{}" }
        if reason == "unconsumed" || reason == "idle" {
            let work = try Store.Work(uploadData: saved.work.uploadData, phase: reason == "idle" ? .idle : .running,
                attemptID: reason == "idle" ? nil : saved.work.attemptID)
            job.metadataJSON = String(decoding: try work.storedData(), as: UTF8.self)
        }
        if reason == "receipt" { try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID, childID: seed.preparation.identity.analysisID).record(in: context) }
        try context.save()
        #expect(throws: (any Error).self) { try Store.readSyncedForSettlement(proof: proof, container: seed.container, isCurrent: { reason != "account" }) }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test(arguments: [false, true])
    func syncedLegacyUppercaseParentRequiresExactStoredParent(forgedLowerParent: Bool) throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("uppercase.store"), fixture = ObservationReanalysisSourceTests()
        let original = try fixture.seed(version: 3, url: url), container = original.container
        let context = ModelContext(container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let old = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        let observation = try #require(UUID(uuidString: "abcdefab-0000-4000-8000-000000000001"))
        let lower = observation.uuidString.lowercased(), upper = observation.uuidString
        #expect(lower != upper)
        let sourceBytes = Data(String(decoding: old.resultSnapshotData, as: UTF8.self)
            .replacingOccurrences(of: original.observationID.uuidString.lowercased(), with: lower).utf8)
        parent.id = upper
        context.delete(old); try context.save()
        let sourceRecord = try LocalAnalysisRecord(analysisID: original.result.analysisID, observationID: upper,
            ownerAccountID: fixture.fixture.owner, completedAt: nil, snapshotVersion: 3, resultSnapshotData: sourceBytes)
        context.insert(sourceRecord); parent.analysisRecords = [sourceRecord]; try context.save()
        let source = try ObservationReanalysisSource.captureForVideo(observationID: observation, ownerID: fixture.fixture.owner, container: container)
        let template = try ObservationHistorySyncTests().videoSnapshot()
        let templateParent = try #require(template["observation_id"] as? String)
        let manifest = try JSONSerialization.data(withJSONObject: #require(template["evidence_manifest"]))
        let childID = try #require(UUID(uuidString: "abcdefab-0000-4000-8000-000000000002"))
        let templateChild = try #require(template["analysis_id"] as? String)
        #expect(childID != source.analysisID && childID != observation)
        let reboundManifest = String(decoding: manifest, as: UTF8.self)
            .replacingOccurrences(of: templateParent, with: lower)
            .replacingOccurrences(of: templateChild, with: childID.uuidString.lowercased())
        let request = try ObservationVideoReanalysisRequest(observationID: observation,
            analysisID: childID, sourceAnalysisID: source.analysisID, manifestBytes: Data(reboundManifest.utf8))
        let preparation = try ObservationVideoPreparation(request: request, source: source), proof = try preparation.verified(source: source)
        // Metadata-only fixture: real protected-file production is covered by the durability suite.
        _ = try ObservationVideoPreparationStore.begin(proof, container: container, isCurrent: { true })
        try ObservationVideoPreparationStore.validate(proof, container: container, isCurrent: { true }, makeReady: true)
        typealias Reservation = ObservationVideoSourceReservationStore
        let staged = try Reservation.stage(.init(video: request), proof: proof, container: container, isCurrent: { true })
        let reserved = try Reservation.settle(Reservation.claim(staged, proof: proof, container: container, isCurrent: { true }),
            settlement: .reply(ObservationVideoReservationLifecycleTests().reply(staged)), proof: proof, container: container, isCurrent: { true })
        _ = try ObservationVideoUploadStore.stage(reserved, proof: proof, container: container, isCurrent: { true })
        typealias Upload = ObservationVideoUploadLifecycleStore
        let uploadClaim = try Upload.claim(Upload.read(proof: proof, container: container, isCurrent: { true }),
            proof: proof, container: container, isCurrent: { true })
        let ready = try Upload.settle(uploadClaim, receipt: ObservationVideoUploadLifecycleTests().receipt(uploadClaim, all: true),
            proof: proof, container: container, isCurrent: { true })
        let auth = ObservationVideoExecutionStoreTests().authorization
        let execution = try Store.stage(ready, proof: proof, authorization: auth, container: container, isCurrent: { true })
        _ = try Store.consume(Store.claim(execution, proof: proof, container: container, isCurrent: { true }),
            proof: proof, authorization: auth, container: container, isCurrent: { true })
        let bytes = try result(request), decoded = try ObservationReanalysisResult.decode(bytes, matching: request)
        let synced = ModelContext(container), storedParent = try ObservationHistorySyncService.enrolledScan(lower, context: synced)
        if forgedLowerParent {
            synced.insert(try LocalAnalysisRecord(analysisID: request.analysisID, observationID: lower, ownerAccountID: source.ownerID,
                completedAt: decoded.completedAt, snapshotVersion: decoded.version, resultSnapshotData: bytes))
        } else {
            _ = try ObservationHistorySyncService.insert([decoded], into: storedParent, ownerID: source.ownerID, context: synced)
        }
        try synced.save()
        let reopened = try fixture.fixture.container(url: url, seed: false)
        let queued = try #require(ModelContext(reopened).fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        #expect(queued.parentObservationID == lower)
        if forgedLowerParent {
            #expect(throws: (any Error).self) { try Store.readSyncedForSettlement(proof: proof, container: reopened, isCurrent: { true }) }
        } else {
            let recovered = try Store.readSyncedForSettlement(proof: proof, container: reopened, isCurrent: { true })
            _ = try Store.complete(recovered, resultBytes: bytes, proof: proof, container: reopened, isCurrent: { true })
            let finalContext = ModelContext(reopened)
            #expect(try finalContext.fetch(FetchDescriptor<OfflineQueuedScan>()).isEmpty)
            let record = try #require(finalContext.fetch(FetchDescriptor<LocalAnalysisRecord>()).first { $0.id == request.analysisID.uuidString.lowercased() })
            #expect(record.observationID == upper && record.resultSnapshotData == bytes)
        }
    }

    @Test func exactRequestBindingRejectsIdentityDigestManifestAndVersionDrift() throws {
        let row = try ObservationHistorySyncTests().videoSnapshot()
        let request = try ObservationVideoReanalysisRequest(observationID: ObservationHistoryPage.uuid(row["observation_id"]),
            analysisID: ObservationHistoryPage.uuid(row["analysis_id"]), sourceAnalysisID: ObservationHistoryPage.uuid(row["source_analysis_id"]),
            manifestBytes: JSONSerialization.data(withJSONObject: #require(row["evidence_manifest"])))
        let bytes = try result(request)
        let decoded = try ObservationReanalysisResult.decode(bytes, matching: request)
        #expect(decoded.bytes == bytes && decoded.version == 5 && decoded.video != nil && decoded.audio == nil)
        let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for (key, value) in [("observation_id", UUID().uuidString.lowercased() as Any), ("analysis_id", UUID().uuidString.lowercased()),
                             ("source_analysis_id", UUID().uuidString.lowercased()), ("request_digest", String(repeating: "a", count: 64)), ("schema_version", 4)] {
            var changed = original; changed[key] = value
            #expect(throws: (any Error).self) { try ObservationReanalysisResult.decode(JSONSerialization.data(withJSONObject: changed), matching: request) }
        }
        var changed = original, manifest = try #require(original["evidence_manifest"] as? [String: Any])
        manifest["descriptions"] = ["Changed exact content"]
        changed["evidence_manifest"] = manifest
        #expect(throws: (any Error).self) { try ObservationReanalysisResult.decode(JSONSerialization.data(withJSONObject: changed), matching: request) }
    }
}
