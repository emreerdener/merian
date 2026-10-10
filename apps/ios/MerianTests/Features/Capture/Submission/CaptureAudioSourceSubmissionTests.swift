import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureAudioSourceSubmissionTests {
    let fixture = ObservationAudioPreparationTests()

    @Test(arguments: [false, true])
    func uncertainStageNeverHandsOffAndExplicitRetryRetainsIdentity(committed: Bool) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let generation = UUID(), session = CaptureAudioReanalysisSession(source: seed.source, generation: generation, container: seed.container)
        let plan = try session.freeze([.audio(seed.bytes)], generation: generation)
        let service = ObservationAudioSourcePreparation(producer: fixture.producer(seed))
        var starts = 0
        await #expect(throws: (any Error).self) {
            try await session.submitSource(generation: generation, preparation: service, isCurrentAccount: { true },
                isCurrentPresentation: { true }, save: { context in
                    if committed { try context.save() }; throw CocoaError(.fileWriteUnknown)
                }, start: { _, _ in starts += 1; return .started })
        }
        #expect(starts == 0 && session.plan?.analysisID == plan.analysisID)
        let proof = try plan.verify().proof
        if committed { try FileManager.default.removeItem(at: seed.root.appendingPathComponent(proof.preparation.path)) }
        var original: ObservationSourceReservationStore.Snapshot?
        let result = try await session.submitSource(generation: generation, preparation: service, isCurrentAccount: { true },
            isCurrentPresentation: { true }, start: { saved, returned in
                guard case let .source(snapshot) = saved else { Issue.record("Source submission became legacy binding"); return .unavailable }
                #expect(returned.preparation == proof.preparation)
                original = snapshot; starts += 1; return .started
            })
        #expect(result == .started && starts == 1)
        let recovered = try await ObservationAudioSourceResumeStore().read(proof.preparation.identity,
            container: seed.container, isCurrent: { true })
        #expect(recovered.snapshot == original && recovered.proof.preparation.identity.analysisID == plan.analysisID)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: ["staged", "running", "unknown", "reserved", "held", "unavailable", "conflict"])
    func savedSourceSkipsMissingFileAndPreservesExactState(_ state: String) async throws {
        let source = ObservationAudioSourceSubmissionTests(), seed = try await source.fixture.fixture.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try source.state(state, seed: seed)
        try FileManager.default.removeItem(at: seed.file)
        let service = ObservationAudioSourcePreparation(producer: fixture.producer(seed))
        let recovered = try await service.prepare(seed.proof, source: seed.source, bytes: Data(), container: seed.container, isCurrent: { true })
        #expect(recovered == .source(saved))
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
    }

    @Test func existingConsumedExecutionRemainsRecoveryOnly() async throws {
        let execution = ObservationAudioExecutionStoreTests(), seed = try await execution.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let original = try execution.bind(seed), proof = try seed.proof
        let claim = try ObservationAudioExecutionStore.claim(original, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let consumed = try ObservationAudioExecutionStore.consume(claim, proof: proof, container: seed.container, isCurrent: { true })
        try FileManager.default.removeItem(at: seed.file)
        let service = ObservationAudioSourcePreparation(producer: fixture.producer(seed))
        let recovered = try await service.prepare(proof, source: seed.source, bytes: Data(), container: seed.container, isCurrent: { true })
        #expect(recovered == .execution(consumed.snapshot))
        #expect(throws: (any Error).self) {
            try ObservationAudioExecutionStore.claim(consumed.snapshot, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        }
    }

    @Test(arguments: ["malformed", "wrongPhase", "account", "foreignLease", "partial"])
    func invalidSavedSourceNeverFallsBackToFilePreparation(_ damage: String) async throws {
        let source = ObservationAudioSourceSubmissionTests(), seed = try await source.fixture.fixture.ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try source.state("staged", seed: seed)
        let context = ModelContext(seed.container), job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        if damage == "malformed" { job.metadataJSON = "{\"phase\":\"source_reservation\"}" }
        if damage == "wrongPhase" { job.metadataJSON = job.metadataJSON?.replacingOccurrences(of: "source_reservation", with: "audio_preparation") }
        if damage == "partial" { context.delete(job) }
        try context.save()
        try FileManager.default.removeItem(at: seed.file)
        var account = fixture.fixture.account()
        if damage == "foreignLease" { account.begin = { _ in .init(id: UUID(), session: .init(userID: UUID(), isAnonymous: false)) } }
        let service = ObservationAudioSourcePreparation(producer: .init(files: .init(documents: seed.root), ownership: .init(), account: account))
        await #expect(throws: (any Error).self) {
            try await service.prepare(seed.proof, source: seed.source, bytes: seed.bytes, container: seed.container, isCurrent: { damage != "account" })
        }
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
    }

    @Test(arguments: ["presentation", "account", "delete"])
    func scopeLossAfterStageNeverHandsOff(_ change: String) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let generation = UUID(), session = CaptureAudioReanalysisSession(source: seed.source, generation: generation, container: seed.container)
        let plan = try session.freeze([.audio(seed.bytes)], generation: generation)
        let service = ObservationAudioSourcePreparation(producer: fixture.producer(seed))
        var account = true, presentation = true, starts = 0
        await #expect(throws: (any Error).self) {
            try await session.submitSource(generation: generation, preparation: service, isCurrentAccount: { account },
                isCurrentPresentation: { presentation }, save: { context in
                    try context.save()
                    if change == "presentation" { presentation = false }
                    if change == "account" { account = false }
                    if change == "delete" {
                        context.delete(try #require(context.fetch(FetchDescriptor<LocalScanRecord>()).first)); try context.save()
                    }
                }, start: { _, _ in starts += 1; return .started })
        }
        #expect(starts == 0 && session.plan?.analysisID == plan.analysisID)
        if change == "presentation" {
            let saved = try ObservationSourceReservationStore.read(plan.verify().proof.preparation.identity, container: seed.container, isCurrent: { true })
            #expect(saved.identity.analysisID == plan.analysisID)
        }
    }
}
