import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioCompletionTests {
    typealias Store = ObservationAudioExecutionStore
    func result(_ seed: ObservationAudioPreparationTests.Seed) throws -> Data {
        var snapshot = try ObservationAudioResultTests().fixture().1
        let request = try ObservationAudioExecutionIntent(preparation: seed.preparation).request
        snapshot["observation_id"] = request.observationID.uuidString.lowercased()
        snapshot["analysis_id"] = request.analysisID.uuidString.lowercased()
        snapshot["source_analysis_id"] = request.sourceAnalysisID.uuidString.lowercased()
        snapshot["request_digest"] = request.requestDigest
        snapshot["evidence_manifest"] = ObservationAudioReanalysisRequest.manifest(request.evidence)
        snapshot["ordinal"] = 2
        return try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
    }
    func consumed(_ seed: ObservationAudioPreparationTests.Seed) throws -> Store.DispatchPermit {
        let initial = try Store.claim(ObservationAudioExecutionStoreTests().bind(seed), purpose: .initial,
            proof: seed.proof, container: seed.container, isCurrent: { true })
        return try Store.consume(initial, proof: seed.proof, container: seed.container, isCurrent: { true })
    }

    @Test func knownOutcomeSettlesCancelledTaskWithoutChangingSelectionOrSource() async throws {
        let seed = try await ObservationAudioExecutionStoreTests().ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let permit = try consumed(seed), bytes = try result(seed), proof = try seed.proof
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try Store.complete(permit.claim, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true })
        }
        let receipt = try await task.value
        let context = ModelContext(seed.container)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == seed.source.analysisID.uuidString.lowercased())
        #expect(parent.observationStateRevision == 10)
        let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.id == seed.source.analysisID.uuidString.lowercased() }?.resultSnapshotData == seed.source.snapshot)
        let child = try #require(records.first { $0.id == receipt.childID.uuidString.lowercased() })
        #expect(child.resultSnapshotData == bytes && child.state == nil)
        #expect(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).isEmpty)
        #expect(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: child.id)) == nil)
        let cleanup = try #require(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID)))
        #expect(try ObservationReanalysisErasureReceipt.restore(cleanup) == receipt)
        #expect(FileManager.default.fileExists(atPath: seed.file.path))
        #expect(try Store.complete(permit.claim, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }) == receipt)
    }

    @Test(arguments: [false, true])
    func completionSaveAmbiguityKeepsOneResultAndOneCleanupReceipt(committed: Bool) async throws {
        let seed = try await ObservationAudioExecutionStoreTests().ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let permit = try consumed(seed), bytes = try result(seed), proof = try seed.proof
        #expect(throws: (any Error).self) {
            try Store.complete(permit.claim, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }, save: { context in
                if committed { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        let context = ModelContext(seed.container)
        #expect(try context.fetch(FetchDescriptor<LocalAnalysisRecord>()).count == (committed ? 2 : 1))
        #expect(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).count == (committed ? 0 : 1))
        _ = try Store.complete(permit.claim, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true })
        #expect(try ModelContext(seed.container).fetch(FetchDescriptor<LocalAnalysisRecord>()).count == 2)
    }

    @Test func onlyCurrentConsumedOrRecoveryClaimCanComplete() async throws {
        let seed = try await ObservationAudioExecutionStoreTests().ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try seed.proof, bytes = try result(seed)
        let first = try Store.claim(ObservationAudioExecutionStoreTests().bind(seed), purpose: .initial,
            proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.complete(first, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }) }
        let permit = try Store.consume(first, proof: proof, container: seed.container, isCurrent: { true })
        try Store.hold(permit.claim, proof: proof, container: seed.container, isCurrent: { true })
        let recovery = try Store.claim(Store.read(proof, container: seed.container, isCurrent: { true }), purpose: .recovery,
            proof: proof, container: seed.container, isCurrent: { true })
        #expect(throws: (any Error).self) { try Store.complete(permit.claim, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true }) }
        _ = try Store.complete(recovery, resultBytes: bytes, proof: proof, container: seed.container, isCurrent: { true })
    }

    @Test(arguments: ["owner", "source", "erasure", "result"])
    func changedScopeOrEvidenceNeverAppends(reason: String) async throws {
        let seed = try await ObservationAudioExecutionStoreTests().ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let permit = try consumed(seed), bytes = try result(seed), proof = try seed.proof
        let context = ModelContext(seed.container)
        if reason == "source" { context.delete(try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)) }
        if reason == "erasure" { _ = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString.lowercased(), context: context) }
        try context.save()
        #expect(throws: (any Error).self) {
            try Store.complete(permit.claim, resultBytes: reason == "result" ? Data("{}".utf8) : bytes,
                proof: proof, container: seed.container, isCurrent: { reason != "owner" })
        }
        #expect(try ModelContext(seed.container).fetch(FetchDescriptor<LocalAnalysisRecord>()).allSatisfy {
            $0.id != seed.preparation.identity.analysisID.uuidString.lowercased()
        })
    }

    struct RestartEvidence {
        let source: ObservationReanalysisSource
        let preparation: ObservationAudioPreparation
        let result: Data
        let request: Data
    }

    @Test(arguments: [false, true])
    func diskRestartAfterCompletionSaveAmbiguityRecoversOutcomeOnly(committed: Bool) async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("completion.store")
        let saved: RestartEvidence = try autoreleasepool {
            let original = try ObservationReanalysisSourceTests().seed(version: 3, url: url)
            let source = try ObservationReanalysisProducerTests().source(original)
            let wav = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 16, sampleAt: { Int16($0) })
            let child = UUID()
            let upload = try ObservationAudioEvidenceUpload(observationID: source.observationID,
                analysisID: child, mediaID: UUID(), bytes: wav).prepare()
            let preparation = try ObservationAudioPreparation(identity: .init(observationID: source.observationID,
                sourceAnalysisID: source.analysisID, analysisID: child, ownerID: source.ownerID),
                evidence: [.description("Before"), .audio(upload.reference), .description("After")], source: source, action: .submit)
            let seed = ObservationAudioPreparationTests.Seed(container: original.container, source: source,
                preparation: preparation, bytes: wav, root: root)
            let proof = try seed.proof
            _ = try ObservationAudioPreparationStore.begin(proof, container: seed.container, isCurrent: { true })
            // Seed only the verified-file boundary; file-lock integration has its own tests.
            try ObservationAudioPreparationStore.validate(proof, container: seed.container, isCurrent: { true }, makeReady: true)
            let permit = try consumed(seed), bytes = try result(seed)
            #expect(throws: (any Error).self) {
                try Store.complete(permit.claim, resultBytes: bytes, proof: proof, container: seed.container,
                    isCurrent: { true }, save: { context in
                        if committed { try context.save() }
                        throw CocoaError(.fileWriteUnknown)
                    })
            }
            return RestartEvidence(source: source, preparation: preparation, result: bytes, request: permit.snapshot.work.intent.request.body)
        }
        let container = try ObservationReanalysisSourceTests().fixture.container(url: url, seed: false)
        let seed = ObservationAudioPreparationTests.Seed(container: container, source: saved.source,
            preparation: saved.preparation, bytes: Data(), root: root)
        let proof = try seed.proof
        let before = ModelContext(container)
        #expect(try before.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == (committed ? 2 : 1))
        #expect(try before.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (committed ? 0 : 1))
        if committed {
            // Durable completion cannot be rediscovered as runnable work after reopening.
            await #expect(throws: (any Error).self) {
                try await ObservationAudioResumeStore.read(saved.preparation.identity, container: container, isCurrent: { true })
            }
        } else {
            let resumed = try await ObservationAudioResumeStore.read(saved.preparation.identity, container: container, isCurrent: { true })
            guard case let .bound(work) = resumed.state else { Issue.record("Lost original execution"); return }
            #expect(work.work.consumedAttempt == 1 && work.work.intent.request.body == saved.request)
            let boundary = try ObservationAudioExecutionServiceTests.Boundary(seed)
            boundary.bytes = saved.result
            try await ObservationAudioInterruptionTests().owned(work, seed: seed) { scope, _ in
                let outcome = await boundary.service.run(work, proof: proof, container: container, scope: scope, cleanup: boundary.cleanup)
                #expect(outcome == .completed)
            }
            #expect(boundary.events == ["outcome", "cleanup"])
        }
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>())
        #expect(records.count == 2)
        #expect(records.first { $0.id == saved.preparation.identity.analysisID.uuidString.lowercased() }?.resultSnapshotData == saved.result)
        #expect(records.first { $0.id == saved.source.analysisID.uuidString.lowercased() }?.resultSnapshotData == saved.source.snapshot)
        let parent = try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == saved.source.analysisID.uuidString.lowercased() && parent.observationStateRevision == 10)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        let receipt = try #require(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(saved.preparation.identity.analysisID)))
        #expect(try ObservationReanalysisErasureReceipt.restore(receipt) == .init(parentID: saved.source.observationID, childID: saved.preparation.identity.analysisID))
    }
}
