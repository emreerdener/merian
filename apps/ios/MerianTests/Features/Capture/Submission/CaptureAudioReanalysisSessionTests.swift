import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureAudioReanalysisSessionTests {
    let fixture = ObservationAudioPreparationTests()

    @Test func tapFreezesIdentityBytesAndOrderBeforeVerification() throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let generation = UUID(), choices: [CaptureAudioReanalysisPlan.Choice] = [.description("Before"), .audio(seed.bytes), .description("After")]
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: generation, container: seed.container)
        let first = try session.freeze(choices, generation: generation)
        let retry = try session.freeze(choices, generation: generation)
        #expect(first.analysisID == retry.analysisID && first.mediaID == retry.mediaID)
        #expect(first.source == seed.source && first.choices == choices)
        let prepared = try first.verify(), repeated = try retry.verify()
        #expect(prepared.bytes == seed.bytes && prepared.proof.preparation == repeated.proof.preparation)
        #expect(prepared.proof.preparation.evidence == [.description("Before"), .audio(prepared.proof.preparation.audio), .description("After")])
        #expect(throws: (any Error).self) { try session.freeze([.audio(seed.bytes)], generation: generation) }
        #expect(throws: (any Error).self) { try session.freeze(choices, generation: UUID()) }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }

    @Test(arguments: [false, true])
    func failedSaveRetainsSamePlanAndBoundRetrySkipsMissingFiles(committed: Bool) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let generation = UUID(), owner = ObservationReanalysisPreparationOwner(), account = fixture.fixture.account()
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: generation, container: seed.container)
        let plan = try session.freeze([.description("Exact text"), .audio(seed.bytes)], generation: generation)
        let producer = ObservationAudioPreparationProducer(files: .init(documents: seed.root), ownership: owner, account: account)
        var consent = 0, starts = 0
        let binding = ObservationAudioSubmissionBinding(ownership: owner, account: account, authorize: { _, validate in
            try validate(); consent += 1; return .init(recipient: .gemini, validate: validate)
        })
        await #expect(throws: (any Error).self) {
            try await session.submit(generation: generation, producer: producer, binding: binding,
                isCurrentAccount: { true }, isCurrentPresentation: { true }, save: { context in
                    if committed { try context.save() }; throw CocoaError(.fileWriteUnknown)
                }, start: { _, _ in starts += 1; return .started })
        }
        #expect(starts == 0 && consent == 1 && session.plan?.analysisID == plan.analysisID)
        let proof = try plan.verify().proof
        if committed { try FileManager.default.removeItem(at: seed.root.appendingPathComponent(proof.preparation.path)) }
        var saved: ObservationAudioExecutionStore.Snapshot?
        let result = try await session.submit(generation: generation, producer: producer, binding: binding,
            isCurrentAccount: { true }, isCurrentPresentation: { true }, start: { snapshot, returned in
                #expect(returned.preparation == proof.preparation)
                saved = snapshot; starts += 1; return .unavailable
            })
        #expect(result == .unavailable && consent == (committed ? 1 : 2) && starts == 1)
        let retry = try await session.submit(generation: generation, producer: producer, binding: binding,
            isCurrentAccount: { true }, isCurrentPresentation: { true }, start: { snapshot, _ in
                #expect(snapshot == saved); starts += 1; return .started
            })
        #expect(retry == .started && consent == (committed ? 1 : 2) && starts == 2)
        let context = ModelContext(seed.container)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 1)
    }

    @Test(arguments: ["presentation", "account", "source"])
    func staleScopeAfterAuthorizationWithholdsQueueHandoff(change: String) async throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let generation = UUID(), owner = ObservationReanalysisPreparationOwner(), account = fixture.fixture.account()
        let session = CaptureAudioReanalysisSession(source: seed.source, generation: generation, container: seed.container)
        let plan = try session.freeze([.audio(seed.bytes)], generation: generation)
        let producer = ObservationAudioPreparationProducer(files: .init(documents: seed.root), ownership: owner, account: account)
        var accountCurrent = true, presentationCurrent = true, starts = 0
        let binding = ObservationAudioSubmissionBinding(ownership: owner, account: account, authorize: { _, validate in
            try validate()
            if change == "presentation" { presentationCurrent = false }
            if change == "account" { accountCurrent = false }
            if change == "source" {
                let context = ModelContext(seed.container)
                let record = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
                context.delete(record); try context.save()
            }
            return .init(recipient: .gemini, validate: validate)
        })
        await #expect(throws: (any Error).self) {
            try await session.submit(generation: generation, producer: producer, binding: binding,
                isCurrentAccount: { accountCurrent }, isCurrentPresentation: { presentationCurrent }, start: { _, _ in
                    starts += 1; return .started
                })
        }
        #expect(starts == 0 && session.plan?.analysisID == plan.analysisID)
        if change == "presentation" {
            guard case .bound = try ObservationAudioExecutionStore.admissionState(plan.verify().proof, container: seed.container, isCurrent: { true }) else {
                Issue.record("Presentation loss must not invalidate common binding scope"); return
            }
        }
    }

    @Test func invalidMediaAndChangedEvidenceNeverCreatePreparation() throws {
        let seed = try fixture.seed(); defer { try? FileManager.default.removeItem(at: seed.root) }
        let invalidChoices: [[CaptureAudioReanalysisPlan.Choice]] = [[], [.audio(Data())], [.audio(seed.bytes), .audio(seed.bytes)], [.description("Only text")]]
        for choices in invalidChoices {
            #expect(throws: (any Error).self) { try CaptureAudioReanalysisPlan(source: seed.source, choices: choices) }
        }
        let invalid = try CaptureAudioReanalysisPlan(source: seed.source, choices: [.audio(seed.bytes), .description(" ")])
        #expect(throws: (any Error).self) { try invalid.verify() }
        #expect(try ModelContext(seed.container).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
    }
}
