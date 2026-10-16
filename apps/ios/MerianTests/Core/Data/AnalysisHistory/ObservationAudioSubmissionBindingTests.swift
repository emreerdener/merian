import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioSubmissionBindingTests {
    typealias Store = ObservationAudioExecutionStore
    let fixture = ObservationAudioExecutionStoreTests()

    @Test func discoveryDistinguishesExactPreparationAndBindingWithoutWriting() async throws {
        let seed = try fixture.fixture.seed(action: .submit); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try seed.proof
        guard case .unprepared = try Store.admissionState(proof, container: seed.container, isCurrent: { true }) else {
            Issue.record("Expected exact absence"); return
        }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        _ = try fixture.fixture.phase(seed)
        guard case .preparation(.pending) = try Store.admissionState(proof, container: seed.container, isCurrent: { true }) else {
            Issue.record("Expected pending files"); return
        }
        _ = try await fixture.fixture.producer(seed).prepare(seed.preparation, source: seed.source, bytes: seed.bytes,
            container: seed.container, isCurrent: { true })
        guard case .preparation(.admissionPending) = try Store.admissionState(proof, container: seed.container, isCurrent: { true }) else {
            Issue.record("Expected submitted preparation"); return
        }
        let saved = try fixture.bind(seed)
        guard case let .bound(recovered) = try Store.admissionState(proof, container: seed.container, isCurrent: { true }) else {
            Issue.record("Expected exact binding"); return
        }
        #expect(recovered == saved)
    }

    @Test(arguments: ["missingMetadata", "malformed", "unknown", "damagedExecution", "missingRow", "missingJob", "wrongChild", "account"])
    func damagedOrStaleWorkNeverBecomesAbsence(change: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let context = ModelContext(seed.container)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        switch change {
        case "missingMetadata": job.metadataJSON = nil
        case "malformed": job.metadataJSON = "{"
        case "damagedExecution": job.metadataJSON = "{\"kind\":\"audio_execution\"}"
        case "unknown": job.metadataJSON = "{\"kind\":\"unknown\"}"
        case "missingRow": context.delete(try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first))
        case "missingJob": context.delete(job)
        case "wrongChild": job.subjectId = UUID().uuidString.lowercased()
        default: break
        }
        try context.save()
        #expect(throws: (any Error).self) {
            try Store.admissionState(seed.proof, container: seed.container, isCurrent: { change != "account" })
        }
    }

    @Test(arguments: [false, true])
    func ambiguousBindRecoversSameRequestWithoutRepeatingConsent(committed: Bool) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try seed.proof, ownership = ObservationReanalysisPreparationOwner()
        var authorizations = 0, finished = 0
        let binding = ObservationAudioSubmissionBinding(ownership: ownership,
            account: fixture.fixture.fixture.account(finish: { finished += 1 }), authorize: { owner, validate in
                #expect(owner == seed.source.ownerID); try validate(); authorizations += 1
                return .init(recipient: .gemini, validate: validate)
            })
        await #expect(throws: (any Error).self) {
            try await binding.bind(proof, container: seed.container, isCurrent: { true }, save: { context in
                if committed { try context.save() }
                throw CocoaError(.fileWriteUnknown)
            })
        }
        #expect(finished == 1 && !ownership.contains(seed.preparation.identity.analysisID))
        let recovered = try await binding.bind(proof, container: seed.container, isCurrent: { true })
        #expect(authorizations == (committed ? 1 : 2) && finished == 2)
        #expect(recovered.work.intent.request.body == (try ObservationAudioExecutionIntent(preparation: seed.preparation)).request.body)
        #expect(recovered.work.state == .idle && recovered.work.consumedAttempt == nil)
        let claim = try Store.claim(recovered, purpose: .initial, proof: proof, container: seed.container, isCurrent: { true })
        let permit = try Store.consume(claim, proof: proof, container: seed.container, isCurrent: { true })
        let consumed = try await binding.bind(proof, container: seed.container, isCurrent: { true })
        #expect(consumed == permit.snapshot && authorizations == (committed ? 1 : 2))
    }

    @Test(arguments: ["drain", "account", "cancel"])
    func authorizationIsRetainedAndStaleAnswerCannotBind(change: String) async throws {
        let seed = try await fixture.ready(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let proof = try seed.proof, ownership = ObservationReanalysisPreparationOwner()
        let entered = AsyncStream<Void>.makeStream(), cancelled = AsyncStream<Void>.makeStream()
        defer { entered.continuation.finish(); cancelled.continuation.finish() }
        var release: CheckedContinuation<Void, Never>?, finished = false, current = true, drained = false
        let binding = ObservationAudioSubmissionBinding(ownership: ownership,
            account: fixture.fixture.fixture.account(finish: { finished = true }), authorize: { _, validate in
                try validate()
                await withTaskCancellationHandler {
                    await withCheckedContinuation { release = $0; entered.continuation.yield(()) }
                } onCancel: { cancelled.continuation.yield(()) }
                return .init(recipient: .gemini, validate: validate)
            })
        let task = Task { try await binding.bind(proof, container: seed.container, isCurrent: { current }) }
        var iterator = entered.stream.makeAsyncIterator(); _ = await iterator.next()
        if change == "account" { current = false }
        if change == "cancel" { task.cancel() }
        let drain = Task {
            if change == "drain" { await ownership.cancelAndAwaitAll(); drained = true }
        }
        if change != "account" {
            var cancellation = cancelled.stream.makeAsyncIterator(); _ = await cancellation.next()
        }
        #expect(ownership.contains(seed.preparation.identity.analysisID) && !finished && !drained)
        try #require(release).resume()
        await #expect(throws: (any Error).self) { try await task.value }
        await drain.value
        #expect(finished && !ownership.contains(seed.preparation.identity.analysisID))
        guard case .preparation(.admissionPending) = try Store.admissionState(proof, container: seed.container, isCurrent: { true }) else {
            Issue.record("Stale authorization bound work"); return
        }
    }
}
