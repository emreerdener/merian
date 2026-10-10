import CryptoKit
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoDurabilityTests {
    struct Seed {
        let root: URL
        let storeURL: URL
        let container: ModelContainer
        let source: ObservationReanalysisSource
        let preparation: ObservationVideoPreparation
        let cohort: ObservationVideoCohort
        let media: VideoAudioFixture
        var proof: ObservationVideoPreparation.Verified { get throws { try preparation.verified(source: source) } }
        func remove() { media.remove(); try? FileManager.default.removeItem(at: root) }
    }
    enum Simulated: Error { case save }

    func seed(audio: Bool = true) async throws -> Seed {
        let root = try ObservationReanalysisFileStoreTests().directory(), url = root.appendingPathComponent("history.store")
        let fixture = ObservationReanalysisSourceTests()
        let history = try fixture.seed(version: 3, url: url)
        let source = try ObservationReanalysisSource.captureForVideo(observationID: history.observationID,
            ownerID: fixture.fixture.owner, container: history.container)
        let media = try await VideoAudioFixture(channels: audio ? 1 : nil)
        let cohort = try await ObservationVideoCohortPreparer().prepare(source: media.videoURL, directory: media.outputDirectory,
            observationID: source.observationID, analysisID: UUID(), sourceAnalysisID: source.analysisID,
            descriptions: [], cropCenterBasisPoints: 5000, inferenceLongEdge: 768)
        return Seed(root: root, storeURL: url, container: history.container, source: source,
                    preparation: try .init(request: cohort.request, source: source), cohort: cohort, media: media)
    }
    func producer(_ seed: Seed) -> ObservationVideoPreparationProducer {
        .init(files: .init(documents: seed.root), ownership: .init(), account: ObservationReanalysisProducerTests().account())
    }
    private func assertBytes(_ seed: Seed) throws {
        for file in seed.preparation.files {
            let bytes = try Data(contentsOf: seed.root.appendingPathComponent(file.path))
            #expect(bytes.count == file.artifact.byteCount)
            #expect(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == file.artifact.sha256)
        }
    }

    @Test(arguments: [false, true])
    func completeCohortSurvivesDiskReopenWithoutDispatch(audio: Bool) async throws {
        let seed = try await seed(audio: audio); defer { seed.remove() }
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
            container: seed.container, isCurrent: { true }) == .ready)
        try assertBytes(seed)
        let store = ObservationReanalysisFileStore(documents: seed.root)
        var readChecks = 0, returnChecks = 0
        let saved = try await store.readVideo(preparation: seed.preparation,
            validateBeforeRead: { readChecks += 1 }, validateBeforeReturn: { returnChecks += 1 })
        #expect(saved.map(\.artifact) == seed.preparation.files.map(\.artifact))
        #expect(saved.count == (audio ? 7 : 6) && readChecks == 1 && returnChecks == 1)
        for (item, file) in zip(saved, seed.preparation.files) {
            #expect(item.bytes == (try Data(contentsOf: seed.root.appendingPathComponent(file.path))))
        }
        #expect(try await store.readVideo(preparation: seed.preparation, validateBeforeRead: {}, validateBeforeReturn: {}) == saved)
        #expect(try seed.media.outputFiles().isEmpty)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: nil,
            container: reopened, isCurrent: { true }) == .ready)
        let context = ModelContext(reopened)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(row.id == seed.preparation.identity.analysisID.uuidString.lowercased())
        #expect(row.inferenceImagePaths == nil && !row.permitsOrdinaryInference)
        #expect(row.serializedCapturedMediaItems == seed.preparation.media)
        #expect(job.statusRaw == OfflineJobStatus.needsAttention.rawValue && job.attemptCount == 0)
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.preparation(seed.preparation.identity, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.restore(row: row, job: job) }
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.discardPreparation(source: seed.source,
            analysisID: seed.preparation.identity.analysisID, container: reopened, isCurrent: { true }) }
        #expect(try ObservationReanalysisAdmissionStore.candidates(ownerID: seed.source.ownerID, canPreflight: true,
            now: Date(), container: reopened, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: seed.source.ownerID,
            container: reopened, isCurrent: { true }).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
    }

    @Test(arguments: [false, true])
    func reservationStageReopensExactCandidateAndRemainsHeld(audio: Bool) async throws {
        let seed = try await seed(audio: audio); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
            container: seed.container, isCurrent: { true })
        let request = try ObservationVideoSourceReservationRequest(video: seed.preparation.request)
        let staged = try ObservationVideoSourceReservationStore.stage(request, proof: seed.proof,
            container: seed.container, isCurrent: { true })
        #expect(try ObservationVideoSourceReservationStore.stage(request, proof: seed.proof,
            container: seed.container, isCurrent: { true }, save: { _ in Issue.record("Replay attempted a save") }) == staged)
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        let restored = try ObservationVideoSourceReservationStore.read(proof: seed.proof, container: reopened, isCurrent: { true })
        #expect(restored.work == staged.work && restored.metadata == staged.metadata)
        #expect(restored.containerID == ObjectIdentifier(reopened))
        #expect(restored.work.request.input == seed.preparation.request.body && restored.work.request.body == request.body)
        let context = ModelContext(reopened)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(row.queueNeedsAttention && row.queueAttemptCount == 0 && !row.permitsOrdinaryInference)
        #expect(job.statusRaw == OfflineJobStatus.needsAttention.rawValue && job.attemptCount == 0 && job.nextRunAt == nil)
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.discard(seed.proof, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.read(seed.proof, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.validate(seed.proof, container: reopened, isCurrent: { true }, expectedPhase: .ready) }
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.restore(row: row, job: job) }
        #expect(throws: (any Error).self) { try ObservationReanalysisPersistence.discardPreparation(source: seed.source,
            analysisID: seed.preparation.identity.analysisID, container: reopened, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoPreparation.requireNonVideo(Data(restored.metadata.utf8)) }
        #expect(try ObservationReanalysisAdmissionStore.candidates(ownerID: seed.source.ownerID, canPreflight: true,
            now: Date(), container: reopened, isCurrent: { true }).isEmpty)
        #expect(try ObservationReanalysisExecutionStore.candidates(ownerID: seed.source.ownerID,
            container: reopened, isCurrent: { true }).isEmpty)
        let siblingRequest = try ObservationVideoReanalysisRequest(observationID: seed.source.observationID, analysisID: UUID(),
            sourceAnalysisID: seed.source.analysisID, manifestBytes: seed.preparation.request.manifest.originalBytes)
        let sibling = try ObservationVideoPreparation(request: siblingRequest, source: seed.source)
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.begin(sibling.verified(source: seed.source),
            container: reopened, isCurrent: { true }) }
        try assertBytes(seed)
    }

    @Test(arguments: [false, true])
    func uncertainReservationStageRetainsSameCandidate(commits: Bool) async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
            container: seed.container, isCurrent: { true })
        let request = try ObservationVideoSourceReservationRequest(video: seed.preparation.request)
        #expect(throws: Simulated.save) {
            try ObservationVideoSourceReservationStore.stage(request, proof: seed.proof, container: seed.container,
                isCurrent: { true }, save: { if commits { try $0.save() }; throw Simulated.save })
        }
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        if commits {
            #expect(try ObservationVideoSourceReservationStore.read(proof: seed.proof, container: reopened,
                isCurrent: { true }).work.request == request)
        } else {
            #expect(throws: (any Error).self) { try ObservationVideoSourceReservationStore.read(proof: seed.proof, container: reopened, isCurrent: { true }) }
            #expect(try ObservationVideoPreparationStore.read(seed.proof, container: reopened, isCurrent: { true }) == .ready)
        }
        let retry = try ObservationVideoSourceReservationStore.stage(request, proof: seed.proof, container: reopened, isCurrent: { true })
        #expect(retry.work.request == request)
        #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        try assertBytes(seed)
    }

    @Test(arguments: ["missing", "pending", "account", "attempt", "owner", "deleted", "malformed", "snapshot", "oversized"])
    func reservationStageRejectsInvalidScopeWithoutRearming(reason: String) async throws {
        let seed = try await seed(); defer { seed.remove() }
        let request = try ObservationVideoSourceReservationRequest(video: seed.preparation.request)
        if reason != "missing" {
            _ = try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
            if reason != "pending" {
                _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
                    container: seed.container, isCurrent: { true })
            }
            let context = ModelContext(seed.container)
            let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
            let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
            if reason == "attempt" { job.attemptCount = 1 }
            if reason == "owner" { row.reanalysisOwnerAccountID = UUID().uuidString.lowercased() }
            if reason == "malformed" { job.metadataJSON = "{\"kind\":\"video_source_reservation\",\"phase\":\"unknown\"}" }
            if reason == "oversized" { job.metadataJSON = String(repeating: " ", count: ObservationVideoSourceReservationWork.maximumBytes + 1) }
            if reason == "deleted" || reason == "snapshot" {
                let source = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
                if reason == "snapshot" {
                    let replacement = try LocalAnalysisRecord(analysisID: seed.source.analysisID,
                        observationID: source.observationID, ownerAccountID: seed.source.ownerID,
                        completedAt: source.completedAt, snapshotVersion: source.snapshotVersion, resultSnapshotData: Data("{}".utf8))
                    context.delete(source)
                    try context.save()
                    context.insert(replacement)
                } else { context.delete(source) }
            }
            try context.save()
        }
        #expect(throws: (any Error).self) { try ObservationVideoSourceReservationStore.stage(request, proof: seed.proof,
            container: seed.container, isCurrent: { reason != "account" }) }
        #expect(throws: (any Error).self) { try ObservationVideoSourceReservationStore.read(proof: seed.proof,
            container: seed.container, isCurrent: { reason != "account" }) }
        let context = ModelContext(seed.container)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (reason == "missing" ? 0 : 1))
        #expect(try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.preparation.identity.analysisID)) == nil)
    }

    @Test(arguments: ["parent", "source", "child", "erasure", "missing", "cancel"])
    func stagedReservationCannotBypassChangedScope(reason: String) async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
            container: seed.container, isCurrent: { true })
        let request = try ObservationVideoSourceReservationRequest(video: seed.preparation.request)
        _ = try ObservationVideoSourceReservationStore.stage(request, proof: seed.proof, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        switch reason {
        case "parent": row.parentObservationID = UUID().uuidString.lowercased()
        case "source": row.sourceAnalysisID = UUID().uuidString.lowercased()
        case "child": row.id = UUID().uuidString.lowercased()
        case "erasure": try ObservationReanalysisErasureReceipt(parentID: seed.source.observationID,
            childID: seed.preparation.identity.analysisID).record(in: context)
        case "missing": context.delete(row)
        default: break
        }
        try context.save()
        let task = Task { @MainActor in
            if reason == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            #expect(throws: (any Error).self) { try ObservationVideoSourceReservationStore.read(proof: seed.proof,
                container: seed.container, isCurrent: { true }) }
            #expect(throws: (any Error).self) { try ObservationVideoSourceReservationStore.stage(request, proof: seed.proof,
                container: seed.container, isCurrent: { true }) }
        }
        await task.value
        try assertBytes(seed)
    }

    @Test func reservationCodecRejectsSubstitutionAndFutureEnvelopes() async throws {
        let seed = try await seed(); defer { seed.remove() }
        let pretty = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: seed.preparation.request.body), options: [.prettyPrinted, .sortedKeys])
        let video = try ObservationVideoReanalysisRequest(savedBody: pretty)
        let preparation = try ObservationVideoPreparation(request: video, source: seed.source)
        let request = try ObservationVideoSourceReservationRequest(video: video)
        let work = try ObservationVideoSourceReservationWork(preparation: preparation, request: request)
        #expect(try ObservationVideoSourceReservationWork.decode(work.storedData()) == work)
        #expect(work.request.input == pretty)
        #expect(throws: (any Error).self) { try ObservationVideoSourceReservationWork(preparation: seed.preparation, request: request) }
        let valid = try #require(JSONSerialization.jsonObject(with: work.storedData()) as? [String: Any])
        var maximumEnvelope = valid
        maximumEnvelope["preparation_base64"] = Data(repeating: 32, count: ObservationVideoPreparation.maximumStoredBytes).base64EncodedString()
        maximumEnvelope["candidate_base64"] = Data(repeating: 32, count: ObservationVideoSourceReservationRequest.maximumBytes).base64EncodedString()
        #expect(try JSONSerialization.data(withJSONObject: maximumEnvelope).count <= ObservationVideoSourceReservationWork.maximumStagedBytes)
        for key in ["version", "phase", "kind", "extra", "preparation_base64", "candidate_base64"] {
            var changed = valid
            switch key {
            case "version": changed[key] = 2
            case "phase": changed[key] = "running"
            case "preparation_base64": changed[key] = try preparation.storedData(phase: .pending).base64EncodedString()
            case "candidate_base64": changed[key] = try ObservationVideoSourceReservationRequest(video: seed.preparation.request).body.base64EncodedString()
            default: changed[key] = "unsupported"
            }
            #expect(throws: (any Error).self) { try ObservationVideoSourceReservationWork.decode(JSONSerialization.data(withJSONObject: changed)) }
        }
        #expect(throws: (any Error).self) { try ObservationVideoSourceReservationWork.decode(Data(repeating: 32, count: ObservationVideoSourceReservationWork.maximumBytes + 1)) }
    }

    @Test(arguments: [false, true])
    func uncertainPromotionRetainsOriginalCohort(commits: Bool) async throws {
        let seed = try await seed(); defer { seed.remove() }
        #expect(try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true }) == .pending)
        do {
            _ = try await seed.cohort.persist(preparation: seed.preparation, store: .init(documents: seed.root), validateBeforeWrite: {
                try ObservationVideoPreparationStore.validate(seed.proof, container: seed.container, isCurrent: { true })
            }, commit: {
                try ObservationVideoPreparationStore.validate(seed.proof, container: seed.container, isCurrent: { true }, makeReady: true, save: {
                    if commits { try $0.save() }; throw Simulated.save
                })
                return true
            })
            Issue.record("Save failure was not returned")
        } catch Simulated.save {}
        try assertBytes(seed)
        #expect(!(try seed.media.outputFiles().isEmpty))
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        #expect(try ObservationVideoPreparationStore.read(seed.proof, container: reopened, isCurrent: { true }) == (commits ? .ready : .pending))
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: nil,
            container: reopened, isCurrent: { true }) == .ready)
        try assertBytes(seed)
    }

    @Test(arguments: ["missing", "changed", "digest", "extra", "symlink", "audio"])
    func recoveryNeverRepairsIncompleteCohort(damage: String) async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort, container: seed.container, isCurrent: { true })
        let reference = seed.preparation.files[damage == "audio" ? seed.preparation.files.count - 1 : 1]
        let file = seed.root.appendingPathComponent(reference.path)
        switch damage {
        case "missing", "audio": try FileManager.default.removeItem(at: file)
        case "changed": try Data([0]).write(to: file)
        case "digest": try Data(repeating: 0, count: reference.artifact.byteCount).write(to: file)
        case "extra": try Data([0]).write(to: file.deletingLastPathComponent().appendingPathComponent("extra"))
        default:
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: seed.media.videoURL)
        }
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: nil, container: seed.container, isCurrent: { true })
        }
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisFileStore(documents: seed.root).readVideo(preparation: seed.preparation,
                validateBeforeRead: {}, validateBeforeReturn: { Issue.record("Damaged cohort returned bytes") })
        }
        #expect(try seed.media.outputFiles().isEmpty)
        if damage == "missing" || damage == "audio" { #expect(!FileManager.default.fileExists(atPath: file.path)) }
        #expect(try ObservationVideoPreparationStore.read(seed.proof, container: seed.container, isCurrent: { true }) == .ready)
    }

    @Test func recoveryCannotInsertMissingWorkAndAccountFencePrecedesWrites() async throws {
        let seed = try await seed(); defer { seed.remove() }
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: nil, container: seed.container, isCurrent: { true })
        }
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort, container: seed.container, isCurrent: { false })
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: seed.root.appendingPathComponent("ReanalysisQueue").path))
    }

    @Test func pendingSaveFailureNeverCopiesFiles() async throws {
        let seed = try await seed(); defer { seed.remove() }
        #expect(throws: Simulated.self) {
            try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true }, save: { _ in throw Simulated.save })
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(!FileManager.default.fileExists(atPath: seed.root.appendingPathComponent("ReanalysisQueue").path))
    }

    @Test func deletionInsideFileFencePreventsPublication() async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
        await #expect(throws: (any Error).self) {
            try await seed.cohort.persist(preparation: seed.preparation, store: .init(documents: seed.root), validateBeforeWrite: {
                let context = ModelContext(seed.container)
                _ = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString.lowercased(), context: context)
                try context.save()
                try ObservationVideoPreparationStore.validate(seed.proof, container: seed.container, isCurrent: { true })
            }, commit: { Issue.record("Deleted owner reached commit"); return true })
        }
        for file in seed.preparation.files { #expect(!FileManager.default.fileExists(atPath: seed.root.appendingPathComponent(file.path).path)) }
        #expect(!(try seed.media.outputFiles().isEmpty))
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true }) }
    }

    @Test func copyFailureRetainsExactCohortForSameChildRetry() async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
        await #expect(throws: Simulated.self) {
            try await seed.cohort.persist(preparation: seed.preparation, store: .init(documents: seed.root),
                validateBeforeWrite: { throw Simulated.save }, commit: { Issue.record("Failed validation reached commit"); return true })
        }
        #expect(!(try seed.media.outputFiles().isEmpty))
        #expect(try ObservationVideoPreparationStore.read(seed.proof, container: seed.container, isCurrent: { true }) == .pending)
        #expect(try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
            container: seed.container, isCurrent: { true }) == .ready)
        try assertBytes(seed)
        #expect(try seed.media.outputFiles().isEmpty)
    }

    @Test func parentErasureOwnsAllVideoArtifacts() async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        let cleanup = try ObservationReanalysisErasure.removeChildren(of: seed.source.observationID.uuidString.lowercased(), context: context)
        try context.save()
        #expect(Set(cleanup.mediaPaths) == Set(seed.preparation.files.map { URL.documentsDirectory.appendingPathComponent($0.path).path }))
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.read(seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }
    @Test(arguments: ["pending", "ready", "missing-file"])
    func explicitDiscardFencesReplayAndCleansWholeChild(state: String) async throws {
        let seed = try await seed(); defer { seed.remove() }
        if state == "pending" {
            _ = try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
        } else {
            _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
                container: seed.container, isCurrent: { true })
            if state == "missing-file" { try FileManager.default.removeItem(at: seed.root.appendingPathComponent(seed.preparation.files[1].path)) }
        }
        let cleanup = ObservationReanalysisErasureOwner(files: .init(documents: seed.root))
        let receipt = try await producer(seed).discard(seed.preparation, source: seed.source,
            container: seed.container, cleanup: cleanup, isCurrent: { true })
        let context = ModelContext(seed.container)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        let storedReceipt = try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(receipt.childID))
        let job = try #require(storedReceipt)
        #expect(job.statusRaw == OfflineJobStatus.complete.rawValue)
        for file in seed.preparation.files { #expect(!FileManager.default.fileExists(atPath: seed.root.appendingPathComponent(file.path).path)) }
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.validate(seed.proof, container: seed.container, isCurrent: { true }, makeReady: true) }
        // A durable receipt remains replayable after the source has gone.
        for record in try context.fetch(FetchDescriptor<LocalAnalysisRecord>()) { context.delete(record) }
        try context.save()
        #expect(try await producer(seed).discard(seed.preparation, source: seed.source,
            container: seed.container, cleanup: cleanup, isCurrent: { true }) == receipt)
    }

    @Test(arguments: [false, true])
    func discardSaveUncertaintyRecoversOnlyCommittedReceipt(commits: Bool) async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
        #expect(throws: Simulated.self) {
            try ObservationVideoPreparationStore.discard(seed.proof, container: seed.container, isCurrent: { true }, save: {
                if commits { try $0.save() }; throw Simulated.save
            })
        }
        let reopened = try ObservationPublicationPersistenceTests().container(url: seed.storeURL, seed: false)
        let context = ModelContext(reopened)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (commits ? 0 : 1))
        #expect((try context.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.preparation.identity.analysisID)) != nil) == commits)
        let receipt = try ObservationVideoPreparationStore.discard(seed.proof, container: reopened, isCurrent: { true })
        #expect(receipt.childID == seed.preparation.identity.analysisID)
        #expect(try ObservationVideoPreparationStore.discard(seed.proof, container: reopened, isCurrent: { true }) == receipt)
    }

    @Test(arguments: ["attempt", "unknown", "owner", "missing-job", "account"])
    func discardRejectsUnprovenStateWithoutMutation(reason: String) async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try ObservationVideoPreparationStore.begin(seed.proof, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        switch reason {
        case "attempt": job.attemptCount = 1
        case "unknown": job.metadataJSON = "{}"
        case "owner": row.reanalysisOwnerAccountID = UUID().uuidString.lowercased()
        case "missing-job": context.delete(job)
        default: break
        }
        try context.save()
        #expect(throws: (any Error).self) {
            try ObservationVideoPreparationStore.discard(seed.proof, container: seed.container, isCurrent: { reason != "account" })
        }
        let fresh = ModelContext(seed.container)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try fresh.fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(seed.preparation.identity.analysisID)) == nil)
    }

    @Test func discardCannotCreateReceiptForMissingPreparation() async throws {
        let seed = try await seed(); defer { seed.remove() }
        #expect(throws: (any Error).self) { try ObservationVideoPreparationStore.discard(seed.proof, container: seed.container, isCurrent: { true }) }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test(arguments: ["before", "return", "cancel", "cancelReturn"])
    func savedReadRequiresBothScopesAndCancellation(kind: String) async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
            container: seed.container, isCurrent: { true })
        let store = ObservationReanalysisFileStore(documents: seed.root)
        let task = Task { @MainActor in
            if kind == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
            return try await store.readVideo(preparation: seed.preparation, validateBeforeRead: {
                if kind == "before" { throw Simulated.save }
            }, validateBeforeReturn: {
                if kind == "before" || kind == "cancel" { Issue.record("Invalid scope reached return fence") }
                if kind == "return" { throw Simulated.save }
                if kind == "cancelReturn" { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        await #expect(throws: (any Error).self) { try await task.value }
        // Failed reads release locks and do not erase or mutate the retained bytes.
        let retry = try await store.readVideo(preparation: seed.preparation, validateBeforeRead: {}, validateBeforeReturn: {})
        #expect(retry.map(\.artifact) == seed.preparation.files.map(\.artifact))
        try assertBytes(seed)
    }

    @Test func savedReadHoldsRootAndChildLocksThroughReturnFence() async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort,
            container: seed.container, isCurrent: { true })
        let directory = seed.root.appendingPathComponent(seed.preparation.files[0].path).deletingLastPathComponent()
        let assertLocked: @MainActor @Sendable () throws -> Void = {
            for path in [seed.root.path, directory.path] {
                let descriptor = open(path, O_RDONLY | O_DIRECTORY)
                #expect(descriptor >= 0)
                defer { close(descriptor) }
                #expect(flock(descriptor, LOCK_EX | LOCK_NB) != 0)
            }
        }
        _ = try await ObservationReanalysisFileStore(documents: seed.root).readVideo(preparation: seed.preparation,
            validateBeforeRead: assertLocked, validateBeforeReturn: assertLocked)
        let lock = open(directory.path, O_RDONLY | O_DIRECTORY)
        #expect(lock >= 0); defer { close(lock) }
        #expect(flock(lock, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: ObservationReanalysisFileStore.Failure.busy) {
            try await ObservationReanalysisFileStore(documents: seed.root).readVideo(preparation: seed.preparation,
                validateBeforeRead: { Issue.record("Busy child reached read fence") }, validateBeforeReturn: {})
        }
        #expect(flock(lock, LOCK_UN) == 0)
    }

}
