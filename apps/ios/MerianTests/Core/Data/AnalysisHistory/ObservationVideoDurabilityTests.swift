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

    private func seed(audio: Bool = true) async throws -> Seed {
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
    private func producer(_ seed: Seed) -> ObservationVideoPreparationProducer {
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

    @Test(arguments: ["missing", "changed", "extra", "symlink"])
    func recoveryNeverRepairsIncompleteCohort(damage: String) async throws {
        let seed = try await seed(); defer { seed.remove() }
        _ = try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: seed.cohort, container: seed.container, isCurrent: { true })
        let file = seed.root.appendingPathComponent(seed.preparation.files[1].path)
        switch damage {
        case "missing": try FileManager.default.removeItem(at: file)
        case "changed": try Data([0]).write(to: file)
        case "extra": try Data([0]).write(to: file.deletingLastPathComponent().appendingPathComponent("extra"))
        default:
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: seed.media.videoURL)
        }
        await #expect(throws: (any Error).self) {
            try await producer(seed).prepare(seed.preparation, source: seed.source, cohort: nil, container: seed.container, isCurrent: { true })
        }
        #expect(try seed.media.outputFiles().isEmpty)
        if damage == "missing" { #expect(!FileManager.default.fileExists(atPath: file.path)) }
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
}
