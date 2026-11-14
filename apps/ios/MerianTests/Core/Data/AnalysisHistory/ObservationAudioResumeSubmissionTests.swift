import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor @Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioResumeSubmissionTests {
    let fixture = ObservationAudioExecutionStoreTests()
    typealias Resume = ObservationAudioResumeSubmission

    @Test(arguments: [false, true])
    func saveAmbiguityReopensSameChildAndEveryLeaseFinishesInsideOwner(committed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let owner = ObservationReanalysisPreparationOwner()
        var leases = 0, consent = 0
        let account = fixture.fixture.fixture.account(finish: {
            #expect(owner.contains(seed.preparation.identity.analysisID)); leases += 1
        })
        let service = Resume(producer: .init(files: .init(documents: seed.root), ownership: owner, account: account), authorize: { _, validate in
            try validate(); consent += 1; return .init(recipient: .gemini, validate: validate)
        })
        await #expect(throws: (any Error).self) {
            try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true }, save: { context in
                if committed { try context.save() }; throw CocoaError(.fileWriteUnknown)
            })
        }
        #expect(leases == 3 && consent == 1)
        if committed { try FileManager.default.removeItem(at: seed.file) }
        let resumed = try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
        #expect(resumed.proof.preparation == seed.preparation)
        #expect(resumed.snapshot.work.intent.request.body == (try ObservationAudioExecutionIntent(preparation: seed.preparation)).request.body)
        #expect(consent == (committed ? 1 : 2) && leases == (committed ? 4 : 6))
        #expect(!owner.contains(seed.preparation.identity.analysisID))
    }

    @Test func consumedBindingResumeSkipsFilesAndConsentWithoutClearingMarker() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let saved = try fixture.bind(seed)
        let claim = try ObservationAudioExecutionStore.claim(saved, purpose: .initial, proof: seed.proof, container: seed.container, isCurrent: { true })
        let permit = try ObservationAudioExecutionStore.consume(claim, proof: seed.proof, container: seed.container, isCurrent: { true })
        try FileManager.default.removeItem(at: seed.file)
        let service = Resume(producer: fixture.fixture.producer(seed), authorize: { _, _ in
            Issue.record("Bound recovery requested consent"); throw MerianError.aiConsentRequired
        })
        let result = try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
        #expect(result.snapshot == permit.snapshot && result.snapshot.work.consumedAttempt == 1)
    }

    @Test(arguments: ["valid", "missing", "changed"])
    func pendingResumeOnlyPromotesVerifiedOriginalFile(_ mode: String) async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try fixture.fixture.phase(seed)
        try FileManager.default.createDirectory(at: seed.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if mode != "missing" { try (seed.bytes + (mode == "changed" ? Data([1]) : Data())).write(to: seed.file) }
        var consent = 0
        let service = Resume(producer: fixture.fixture.producer(seed), authorize: { _, validate in
            try validate(); consent += 1; return .init(recipient: .gemini, validate: validate)
        })
        if mode == "valid" {
            let result = try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
            #expect(result.snapshot.work.state == .idle && consent == 1)
        } else {
            await #expect(throws: (any Error).self) {
                try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
            }
            let phase = try fixture.fixture.phase(seed)
            #expect(consent == 0 && phase == .pending)
        }
    }

    @Test(arguments: ["missing", "bound"])
    func existingOnlyRecoveryNeverRecreatesOrRewritesWork(_ mode: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        _ = try await ObservationAudioResumeStore.read(seed.preparation.identity, container: seed.container, isCurrent: { true })
        let context = ModelContext(seed.container)
        if mode == "missing" {
            for row in try context.fetch(FetchDescriptor<OfflineQueuedScan>()) { context.delete(row) }
            for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) { context.delete(job) }
            try context.save()
        } else { _ = try fixture.bind(seed) }
        await #expect(throws: (any Error).self) {
            try await fixture.fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: nil,
                container: seed.container, isCurrent: { true })
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (mode == "missing" ? 0 : 1))
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
    }

    @Test(arguments: ["missing", "bound"])
    func orchestrationGapPreservesMissingOrConcurrentlyBoundChild(_ mode: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        var account = fixture.fixture.fixture.account()
        let begin = account.begin
        var entries = 0, consent = 0
        account.begin = { ownerID in
            entries += 1
            if entries == 2 {
                if mode == "missing" {
                    let context = ModelContext(seed.container)
                    for row in try context.fetch(FetchDescriptor<OfflineQueuedScan>()) { context.delete(row) }
                    for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) { context.delete(job) }
                    try context.save()
                } else { _ = try fixture.bind(seed) }
            }
            return try begin(ownerID)
        }
        let service = Resume(producer: .init(files: .init(documents: seed.root), ownership: .init(), account: account), authorize: { _, validate in
            consent += 1; return .init(recipient: .gemini, validate: validate)
        })
        await #expect(throws: (any Error).self) {
            try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
        }
        #expect(entries == 2 && consent == 0)
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (mode == "missing" ? 0 : 1))
        #expect(try Data(contentsOf: seed.file) == seed.bytes)
        if mode == "bound" {
            let original = try ObservationAudioExecutionStore.read(seed.proof, container: seed.container, isCurrent: { true })
            let recovered = try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true })
            #expect(recovered.snapshot == original && entries == 3 && consent == 0)
        }
    }

    @Test func authDrainAwaitsBindingLeaseAndDoesNotBindStaleAuthorization() async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let owner = ObservationReanalysisPreparationOwner(), entered = AsyncStream<Void>.makeStream(), cancelled = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); cancelled.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, leases = 0, drained = false
        let service = Resume(producer: .init(files: .init(documents: seed.root), ownership: owner,
            account: fixture.fixture.fixture.account(finish: { leases += 1 })), authorize: { _, validate in
                try validate()
                await withTaskCancellationHandler {
                    await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
                } onCancel: { cancelled.continuation.yield(()) }
                return .init(recipient: .gemini, validate: validate)
            })
        let task = Task { try await service.resume(seed.preparation.identity, container: seed.container, isCurrent: { true }) }
        var start = entered.stream.makeAsyncIterator(); _ = await start.next()
        let drain = Task { await owner.cancelAndAwaitAll(); drained = true }
        var stop = cancelled.stream.makeAsyncIterator(); _ = await stop.next()
        #expect(leases == 2 && !drained && owner.contains(seed.preparation.identity.analysisID))
        try #require(release).resume()
        await #expect(throws: (any Error).self) { try await task.value }
        await drain.value
        #expect(leases == 3 && drained && !owner.contains(seed.preparation.identity.analysisID))
        guard case .preparation(.admissionPending) = try ObservationAudioExecutionStore.admissionState(seed.proof, container: seed.container, isCurrent: { true }) else {
            Issue.record("Drain accepted stale binding"); return
        }
    }
}
