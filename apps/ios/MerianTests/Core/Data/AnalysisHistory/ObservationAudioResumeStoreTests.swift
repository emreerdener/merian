import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioResumeStoreTests {
    let fixture = ObservationAudioExecutionStoreTests()

    @Test(arguments: [false, true])
    func originalPreparationRecoversWithoutFilesOrChangingPhase(ready: Bool) async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.fixture.phase(seed)
        if ready {
            _ = try await fixture.fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
                container: seed.container, isCurrent: { true })
            try FileManager.default.removeItem(at: seed.file)
        }
        let context = ModelContext(seed.container)
        let before = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first?.metadataJSON)
        let saved = try await ObservationAudioResumeStore.read(seed.preparation.identity, container: seed.container, isCurrent: { true })
        #expect(saved.source == seed.source && saved.proof.preparation == seed.preparation)
        guard case let .preparation(phase) = saved.state else { Issue.record("Unexpected binding"); return }
        #expect(phase == (ready ? .admissionPending : .pending))
        #expect(try ModelContext(seed.container).fetch(FetchDescriptor<OfflineJobRecord>()).first?.metadataJSON == before)
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
    }

    @Test(arguments: ["idle", "running", "consumed", "held"])
    func boundRecoveryPreservesExactRequestAndConsumedMarker(_ mode: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var expected = try fixture.bind(seed)
        if mode != "idle" {
            let claim = try ObservationAudioExecutionStore.claim(expected, purpose: .initial, proof: seed.proof,
                container: seed.container, isCurrent: { true })
            if mode == "running" { expected = claim.snapshot } else {
                let permit = try ObservationAudioExecutionStore.consume(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
                expected = permit.snapshot
                if mode == "held" {
                    try ObservationAudioExecutionStore.hold(permit.claim, proof: seed.proof, container: seed.container, isCurrent: { true })
                    expected = try ObservationAudioExecutionStore.read(seed.proof, container: seed.container, isCurrent: { true })
                }
            }
        }
        try FileManager.default.removeItem(at: seed.file)
        let saved = try await ObservationAudioResumeStore.read(seed.preparation.identity, container: seed.container, isCurrent: { true })
        guard case let .bound(actual) = saved.state else { Issue.record("Lost bound work"); return }
        #expect(actual == expected && saved.proof.preparation == seed.preparation)
    }

    @Test(arguments: ["owner", "parent", "source", "child", "metadata", "partial", "heldDraft", "account", "row"])
    func invalidExplicitTargetNeverBecomesNewPreparation(_ reason: String) async throws {
        let seed = try fixture.fixture.seed(action: reason == "heldDraft" ? .hold : .submit)
        defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.fixture.phase(seed)
        let identity = seed.preparation.identity
        let target = OfflineQueueWork.Reanalysis(observationID: reason == "parent" ? UUID() : identity.observationID,
            sourceAnalysisID: reason == "source" ? UUID() : identity.sourceAnalysisID,
            analysisID: reason == "child" ? UUID() : identity.analysisID, ownerID: reason == "owner" ? UUID() : identity.ownerID)
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        if reason == "metadata" { job.metadataJSON = "{}" }
        if reason == "partial" { context.delete(job) }
        if reason == "row" {
            let row = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
            row.queueAttemptCount = 1
        }
        try context.save()
        await #expect(throws: (any Error).self) {
            try await ObservationAudioResumeStore.read(target, container: seed.container, isCurrent: { reason != "account" })
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(!FileManager.default.fileExists(atPath: seed.file.path))
    }
}
