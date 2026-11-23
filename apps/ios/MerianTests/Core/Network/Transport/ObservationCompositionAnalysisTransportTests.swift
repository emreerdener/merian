import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationCompositionAnalysisTransportTests {
    @MainActor struct Fixture {
        let seed: ObservationCompositionPreparationTests.Seed
        let permit: ObservationCompositionExecutionStore.DispatchPermit
        let mock = ScopedMockTransport()
        let pinned = PinnedNetworkTransport()
        let session: URLSession
        let dispatcher: AuthenticatedTransportDispatcher
        var transport: ObservationCompositionAnalysisTransport { .init(baseURL: "https://example.supabase.co", dispatcher: dispatcher) }
        init() async throws {
            let store = ObservationCompositionExecutionTests()
            let (prepared, uploaded) = try await store.uploaded()
            seed = prepared
            let initial = try ObservationCompositionExecutionStore.claim(ObservationCompositionExecutionStore.stage(uploaded, proof: seed.proof, authorization: store.authorization, container: seed.container, isCurrent: { true }),
                proof: seed.proof, container: seed.container, isCurrent: { true })
            permit = try ObservationCompositionExecutionStore.consume(initial, proof: seed.proof, authorization: store.authorization, container: seed.container, isCurrent: { true })
            session = mock.makeSession(); pinned.overridingSession = session
            dispatcher = AuthenticatedTransportDispatcher(sessionTransport: pinned)
            dispatcher.overridingAuthUserID = seed.source.ownerID
        }
        func close() { session.invalidateAndCancel(); seed.removeFiles() }
        func receipt(state: String = "complete") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["schema_version": 1,
                "observation_id": seed.source.observationID.uuidString.lowercased(),
                "analysis_id": seed.preparation.identity.analysisID.uuidString.lowercased(), "state": state])
        }
        func send(validate: @escaping @MainActor @Sendable () throws -> Void = {},
                  response: @escaping @MainActor @Sendable () throws -> Void = {}) async throws -> ObservationAnalysisReceipt {
            try await transport.submit(permit, authorization: .init(recipient: .gemini, validate: {}),
                validateAttempt: validate, validateResponse: response)
        }
    }

    @Test(arguments: ["complete", "failed_terminal", "admitted", "dispatched", "draft"])
    func exactRequestAndReceiptUseOneScopedAttempt(state: String) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let data = try fixture.receipt(state: state), body = fixture.permit.snapshot.work.request.body
        let count = OSAllocatedUnfairLock(initialState: 0)
        let status = state == "complete" || state == "failed_terminal" ? 200 : 202
        fixture.mock.register(path: "/analyze-observation") { wire in
            count.withLock { $0 += 1 }
            #expect(MockURLProtocol.bodyData(for: wire) == body)
            #expect(wire.timeoutInterval == 130)
            #expect(wire.httpMethod == "POST")
            #expect(wire.url?.path == "/functions/v1/analyze-observation")
            #expect(wire.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(wire.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(wire.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            #expect(wire.value(forHTTPHeaderField: IdentificationDispatchAuthorization.protocolHeader) == "7")
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["schema_version"] as? Int == 5)
            #expect(payload["identification_protocol"] as? Int == 7)
            #expect(wire.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == "google_gemini")
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        var attempts = 0, responses = 0
        let reply = try await fixture.send(validate: { attempts += 1 }, response: { responses += 1 })
        #expect(reply.state.rawValue == state && attempts == 1 && responses == 1)
        #expect(count.withLock { $0 } == 1)
        #expect(PinnedNetworkTransport.makeConfiguration().timeoutIntervalForResource == 90)
    }

    @Test(arguments: [401, 404, 429, 500, 503, -1])
    func errorsNeverReplayOrRefresh(status: Int) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let count = OSAllocatedUnfairLock(initialState: 0)
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Unexpected refresh"); return true }
        fixture.mock.register(path: "/analyze-observation") { wire in
            count.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil, headerFields: [:])!, Data("{}".utf8))
        }
        await #expect(throws: (any Error).self) { try await fixture.send() }
        #expect(count.withLock { $0 } == 1)
    }

    @Test(arguments: ["owner", "claim", "consent", "recovery-only"])
    func deniedAfterAuthNeverSends(reason: String) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        fixture.mock.register(path: "/analyze-observation") { _ in
            Issue.record("Denied composition reached dispatch"); throw MerianError.invalidResponse
        }
        if reason == "owner" { fixture.dispatcher.overridingAuthUserID = UUID() }
        let authorization: IdentificationDispatchAuthorization = reason == "recovery-only"
            ? .init(recipient: .recoveryOnly, validate: {})
            : .init(recipient: .gemini, validate: { if reason == "consent" { throw MerianError.aiConsentRequired } })
        await #expect(throws: (any Error).self) {
            try await fixture.transport.submit(fixture.permit, authorization: authorization,
                validateAttempt: { if reason == "claim" { throw CancellationError() } }, validateResponse: {})
        }
    }
}
