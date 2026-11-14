import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct NetworkTransportAssemblyTests {
    @Test func clientFactoriesShareLateSessionAndAccountOverrides() async throws {
        let fixture = try await ObservationAudioAnalysisTransportTests.Fixture(); defer { fixture.close() }
        let client = MerianNetworkClient()
        let analysis = client.audioAnalysisTransport(), outcome = client.audioOutcomeTransport()
        client.overridingSession = fixture.session; client.overridingAuthUserID = fixture.seed.source.ownerID
        defer { client.overridingSession = nil; client.overridingAuthUserID = nil }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let receipt = try fixture.receipt(), bytes = try ObservationAudioOutcomeTransportTests().envelope(fixture)
        fixture.mock.register(path: "/analyze-observation") { request in
            calls.withLock { $0 += 1 }
            #expect(request.timeoutInterval == 130)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, receipt)
        }
        fixture.mock.register(path: ObservationAudioOutcomeTransportTests.path) { request in
            calls.withLock { $0 += 1 }
            #expect(request.timeoutInterval == 5)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, bytes)
        }
        let proof = try fixture.seed.proof
        let validate: @MainActor @Sendable () throws -> Void = {
            try ObservationAudioExecutionStore.validate(fixture.permit.claim, proof: proof,
                container: fixture.seed.container, isCurrent: { true })
        }
        #expect(try await client.authenticatedUserIDForInferenceRequest() == fixture.seed.source.ownerID)
        let reply = try await analysis.submit(fixture.permit, authorization: .init(recipient: .gemini, validate: {}),
            validateAttempt: validate, validateResponse: {})
        #expect(reply.state == .complete)
        let result = try await outcome.read(fixture.permit.claim, validateAttempt: validate, validateResponse: {})
        #expect(result == (try ObservationAudioCompletionTests().result(fixture.seed)))
        #expect(calls.withLock { $0 } == 2)
        client.overridingAuthUserID = UUID()
        await #expect(throws: (any Error).self) {
            try await analysis.submit(fixture.permit, authorization: .init(recipient: .gemini, validate: {}),
                validateAttempt: validate, validateResponse: {})
        }
        await #expect(throws: (any Error).self) {
            try await outcome.read(fixture.permit.claim, validateAttempt: validate, validateResponse: {})
        }
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func replacingSessionReachesExistingFactoriesWithoutAuthRetry() async throws {
        let fixture = try await ObservationAudioAnalysisTransportTests.Fixture(); defer { fixture.close() }
        let client = MerianNetworkClient(), outcome = client.audioOutcomeTransport()
        client.overridingSession = fixture.session; client.overridingAuthUserID = fixture.seed.source.ownerID
        client.overridingAuthSessionRefresh = { Issue.record("Audio may not refresh/replay"); return true }
        defer { client.overridingSession = nil; client.overridingAuthUserID = nil; client.overridingAuthSessionRefresh = nil }
        let replacement = ScopedMockTransport(), session = replacement.makeSession()
        defer { session.invalidateAndCancel() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        replacement.register(path: ObservationAudioOutcomeTransportTests.path) { request in
            calls.withLock { $0 += 1 }
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, Data("{}".utf8))
        }
        client.overridingSession = session
        await #expect(throws: (any Error).self) {
            try await outcome.read(fixture.permit.claim, validateAttempt: {}, validateResponse: {})
        }
        #expect(calls.withLock { $0 } == 1)
    }
}
