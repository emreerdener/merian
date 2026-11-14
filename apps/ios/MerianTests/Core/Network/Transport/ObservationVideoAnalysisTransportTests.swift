import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoAnalysisTransportTests {
    @MainActor struct Fixture {
        let seed: ObservationVideoDurabilityTests.Seed
        let permit: ObservationVideoExecutionStore.DispatchPermit
        let mock = ScopedMockTransport()
        let pinned = PinnedNetworkTransport()
        let session: URLSession
        let dispatcher: AuthenticatedTransportDispatcher
        var transport: ObservationVideoAnalysisTransport { .init(baseURL: "https://example.supabase.co", dispatcher: dispatcher) }
        init() async throws {
            let store = ObservationVideoExecutionStoreTests()
            let (prepared, uploaded) = try await store.ready()
            seed = prepared
            let initial = try ObservationVideoExecutionStore.claim(store.stage(seed, uploaded),
                proof: seed.proof, container: seed.container, isCurrent: { true })
            permit = try ObservationVideoExecutionStore.consume(initial, proof: seed.proof, authorization: store.authorization, container: seed.container, isCurrent: { true })
            session = mock.makeSession(); pinned.overridingSession = session
            dispatcher = AuthenticatedTransportDispatcher(sessionTransport: pinned)
            dispatcher.overridingAuthUserID = seed.source.ownerID
        }
        func close() { session.invalidateAndCancel(); seed.remove() }
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
        fixture.mock.register(path: "/analyze-observation-video") { wire in
            count.withLock { $0 += 1 }
            #expect(MockURLProtocol.bodyData(for: wire) == body)
            #expect(wire.timeoutInterval == 130)
            #expect(wire.httpMethod == "POST")
            #expect(wire.url?.path == "/functions/v1/analyze-observation-video")
            #expect(wire.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(wire.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(wire.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
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
        fixture.mock.register(path: "/analyze-observation-video") { wire in
            count.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil, headerFields: [:])!, Data("{}".utf8))
        }
        await #expect(throws: (any Error).self) { try await fixture.send() }
        #expect(count.withLock { $0 } == 1)
    }

    @Test(arguments: ["owner", "claim", "consent", "recipient"])
    func deniedAfterAuthNeverSends(reason: String) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        fixture.mock.register(path: "/analyze-observation-video") { _ in Issue.record("Denied send"); throw MerianError.invalidResponse }
        if reason == "owner" { fixture.dispatcher.overridingAuthUserID = UUID() }
        await #expect(throws: (any Error).self) {
            try await fixture.transport.submit(fixture.permit,
                authorization: .init(recipient: reason == "recipient" ? .recoveryOnly : .gemini, validate: {
                    if reason == "consent" { throw MerianError.aiConsentRequired }
                }), validateAttempt: {
                    if reason == "claim" { throw MerianError.invalidResponse }
                }, validateResponse: {})
        }
    }

    @Test(arguments: ["owner", "scope", "identity", "status", "mime", "actual-size", "declared-size"])
    func malformedOrStaleResponseIsWithheld(reason: String) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let data = try fixture.receipt()
        fixture.mock.register(path: "/analyze-observation-video") { wire in
            if reason == "owner" { fixture.dispatcher.overridingAuthUserID = UUID() }
            let body = reason == "actual-size" ? Data(repeating: 32, count: 4097) : (reason == "identity" ? Data("{}".utf8) : data)
            var headers = ["Content-Type": reason == "mime" ? "text/html" : "application/json"]
            if reason == "declared-size" { headers["Content-Length"] = "4097" }
            return (HTTPURLResponse(url: wire.url!, statusCode: reason == "status" ? 202 : 200,
                httpVersion: nil, headerFields: headers)!, body)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.send(response: { if reason == "scope" { throw MerianError.invalidResponse } })
        }
    }

    @Test func heldPermitCannotSendAgain() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let proof = try fixture.seed.proof
        _ = try ObservationVideoExecutionStore.hold(fixture.permit.snapshot, proof: proof, container: fixture.seed.container, isCurrent: { true })
        fixture.mock.register(path: "/analyze-observation-video") { _ in Issue.record("Stale permit sent"); throw MerianError.invalidResponse }
        await #expect(throws: (any Error).self) {
            try await fixture.send(validate: {
                try ObservationVideoExecutionStore.validateDispatch(fixture.permit, proof: proof,
                    container: fixture.seed.container, isCurrent: { true })
            })
        }
    }

    @Test func closedReceiptRejectsForeignIDsUnknownStatesVersionsAndExtraFields() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let request = fixture.permit.snapshot.work.request
        let row = try #require(JSONSerialization.jsonObject(with: fixture.receipt()) as? [String: Any])
        for (key, value) in [("schema_version", true as Any), ("schema_version", 2), ("observation_id", UUID().uuidString.lowercased()),
                             ("analysis_id", UUID().uuidString.lowercased()), ("state", "retired"), ("outcome", [:])] {
            var changed = row; changed[key] = value
            #expect(throws: (any Error).self) {
                try ObservationAnalysisReceipt.decode(JSONSerialization.data(withJSONObject: changed), videoRequest: request)
            }
        }
        for key in row.keys {
            var changed = row; changed.removeValue(forKey: key)
            #expect(throws: (any Error).self) {
                try ObservationAnalysisReceipt.decode(JSONSerialization.data(withJSONObject: changed), videoRequest: request)
            }
        }
    }

    @Test(arguments: [false, true])
    func cancelledOrExpiredDispatchCannotSend(expired: Bool) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let proof = try fixture.seed.proof
        fixture.mock.register(path: "/analyze-observation-video") { _ in Issue.record("Denied send"); throw MerianError.invalidResponse }
        let task = Task {
            if !expired { withUnsafeCurrentTask { $0?.cancel() } }
            await #expect(throws: (any Error).self) {
                try await fixture.send(validate: {
                    try ObservationVideoExecutionStore.validateDispatch(fixture.permit, proof: proof,
                        container: fixture.seed.container, isCurrent: { true }, now: expired ? .distantFuture : Date())
                })
            }
        }
        await task.value
    }

    @Test func knownReplyDoesNotReapplyDispatchCancellation() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let data = try fixture.receipt()
        fixture.mock.register(path: "/analyze-observation-video") { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        let task = Task {
            try await fixture.send(response: { withUnsafeCurrentTask { $0?.cancel() } })
        }
        #expect(try await task.value.state == .complete)
    }
}
