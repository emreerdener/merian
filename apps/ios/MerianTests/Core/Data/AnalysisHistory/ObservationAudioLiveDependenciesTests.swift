import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioLiveDependenciesTests {
    @Test func consumedRecoveryUsesOnlyExactInjectedOutcomeTransport() async throws {
        let fixture = try await ObservationAudioAnalysisTransportTests.Fixture(); defer { fixture.close() }
        let client = MerianNetworkClient(), calls = OSAllocatedUnfairLock(initialState: 0)
        client.overridingSession = fixture.session; client.overridingAuthUserID = fixture.seed.source.ownerID
        client.overridingInferenceConsentCheck = { Issue.record("Recovery must not request consent") }
        defer { client.overridingSession = nil; client.overridingAuthUserID = nil; client.overridingInferenceConsentCheck = nil }
        let data = try ObservationAudioOutcomeTransportTests().envelope(fixture)
        fixture.mock.register(path: ObservationAudioOutcomeTransportTests.path) { request in
            calls.withLock { $0 += 1 }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        let service = ObservationAudioExecutionService(dependencies: .live(
            files: .init(documents: fixture.seed.root), client: client))
        let proof = try fixture.seed.proof, saved = fixture.permit.snapshot
        var cleanups = 0
        try await ObservationAudioInterruptionTests().owned(saved, seed: fixture.seed) { scope, _ in
            let result = await service.run(saved, proof: proof, container: fixture.seed.container, scope: scope, cleanup: { receipt in
                #expect(receipt.childID == fixture.seed.preparation.identity.analysisID); cleanups += 1
            })
            #expect(result == .completed)
        }
        #expect(calls.withLock { $0 } == 1 && cleanups == 1)
    }

    @Test func explicitEntryHasNoSchedulerOrUnretainedCleanup() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Merian")
        let queue = try String(contentsOf: root.appendingPathComponent("Core/Data/OfflineSync/Services/OfflineQueueManager+AudioExecution.swift"), encoding: .utf8)
        #expect(queue.contains("await erasure.erase(receipt"))
        #expect(queue.components(separatedBy: "scope.maySettleKnownReceipt()").count == 3)
        for forbidden in ["Task {", "Task.detached", "OfflineJobScheduler", "drainPendingReanalysisErasures", "AppDIContainer.shared", "SupabaseManager.shared"] {
            #expect(!queue.contains(forbidden))
        }
        let scheduler = try String(contentsOf: root.appendingPathComponent("Core/Data/OfflineSync/OfflineJobScheduler.swift"), encoding: .utf8)
        #expect(!scheduler.contains("requestAudioExecution"))
    }
}
