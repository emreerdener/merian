import Foundation
@testable import Merian
import os
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationAudioOutcomeTransportTests {
    typealias Fixture = ObservationAudioAnalysisTransportTests.Fixture
    typealias Store = ObservationAudioExecutionStore
    static let path = "/rest/v1/rpc/get_owned_observation_analysis_state"

    func envelope(_ fixture: Fixture, snapshot: Data? = nil) throws -> Data {
        let bytes = try snapshot ?? ObservationAudioCompletionTests().result(fixture.seed)
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = fixture.seed.source.ownerID.uuidString.lowercased()
        state["observation_id"] = fixture.seed.source.observationID.uuidString.lowercased()
        state["selected_analysis_id"] = fixture.seed.source.analysisID.uuidString.lowercased()
        var item = try #require(state["analysis"] as? [String: Any])
        item["snapshot"] = String(decoding: bytes, as: UTF8.self)
        state["analysis"] = item
        return try JSONSerialization.data(withJSONObject: state)
    }
    func transport(_ fixture: Fixture) -> ObservationAudioOutcomeTransport {
        .init(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
    }
    func read(_ fixture: Fixture, response: @escaping @MainActor @Sendable () throws -> Void = {}) async throws -> Data? {
        let proof = try fixture.seed.proof
        return try await transport(fixture).read(fixture.permit.claim, validateAttempt: {
            try Store.validate(fixture.permit.claim, proof: proof, container: fixture.seed.container, isCurrent: { true })
        }, validateResponse: response)
    }
    func register(_ fixture: Fixture, status: Int = 200, data: Data, headers: [String: String] = ["Content-Type": "application/json"]) {
        fixture.mock.register(path: Self.path) { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, data)
        }
    }

    @Test func exactUnselectedTargetUsesReaderTenWithoutInferenceConsent() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let data = try envelope(fixture), expected = try ObservationAudioCompletionTests().result(fixture.seed)
        let request = fixture.permit.snapshot.work.intent.request
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.mock.register(path: Self.path) { wire in
            calls.withLock { $0 += 1 }
            #expect(wire.httpMethod == "POST" && wire.timeoutInterval == 5)
            #expect(wire.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            let body = try #require(MockURLProtocol.bodyData(for: wire))
            let parameters = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(parameters.keys) == ["p_request", "p_reader"])
            #expect(parameters["p_reader"] as? Int == 10)
            let target = try #require(parameters["p_request"] as? [String: Any])
            #expect(Set(target.keys) == ["schema_version", "observation_id", "analysis_id"])
            #expect(target["schema_version"] as? Int == 1)
            #expect(target["observation_id"] as? String == request.observationID.uuidString.lowercased())
            #expect(target["analysis_id"] as? String == request.analysisID.uuidString.lowercased())
            return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        #expect(try await read(fixture) == expected)
        #expect(calls.withLock { $0 } == 1)
        #expect(try ModelContext(fixture.seed.container).fetch(FetchDescriptor<LocalAnalysisRecord>()).count == 1)
    }

    @Test(arguments: [401, 404, 429, 500, 503, -1])
    func errorsNeverRetryRefreshOrBecomeAbsence(status: Int) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Unexpected refresh"); return true }
        fixture.mock.register(path: Self.path) { wire in
            calls.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, Data("{}".utf8))
        }
        await #expect(throws: (any Error).self) { try await read(fixture) }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: ["exact", "code", "message", "extra", "details", "status", "mime"])
    func onlyExactPostgrestMissingCanReturnNil(kind: String) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        var value: [String: Any] = ["code": "P0002", "message": "analysis_history_not_found", "details": NSNull(), "hint": NSNull()]
        if kind == "code" { value["code"] = "PGRST116" }
        if kind == "message" { value["message"] = "not_found" }
        if kind == "extra" { value["extra"] = true }
        if kind == "details" { value["details"] = 1 }
        register(fixture, status: kind == "status" ? 500 : 404, data: try JSONSerialization.data(withJSONObject: value),
            headers: ["Content-Type": kind == "mime" ? "text/html" : "application/json"])
        if kind == "exact" { #expect(try await read(fixture) == nil) }
        else { await #expect(throws: (any Error).self) { try await read(fixture) } }
        #expect(try Store.read(fixture.seed.proof, container: fixture.seed.container, isCurrent: { true }).work.consumedAttempt != nil)
    }

    @Test(arguments: ["owner", "child", "source", "digest", "mime", "actual", "declared", "scope"])
    func invalidStateOrScopeNeverReturnsAnOutcome(kind: String) async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        var bytes = try ObservationAudioCompletionTests().result(fixture.seed)
        if ["child", "source", "digest"].contains(kind) {
            var snapshot = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            let key = kind == "child" ? "analysis_id" : (kind == "source" ? "source_analysis_id" : "request_digest")
            snapshot[key] = kind == "digest" ? String(repeating: "f", count: 64) : UUID().uuidString.lowercased()
            bytes = try JSONSerialization.data(withJSONObject: snapshot)
        }
        var state = try #require(JSONSerialization.jsonObject(with: envelope(fixture, snapshot: bytes)) as? [String: Any])
        if kind == "owner" { state["owner_id"] = UUID().uuidString.lowercased() }
        let data = kind == "actual" ? Data(repeating: 32, count: ObservationHistoryPage.maximumPageBytes + 1)
            : try JSONSerialization.data(withJSONObject: state)
        var headers = ["Content-Type": kind == "mime" ? "text/html" : "application/json"]
        if kind == "declared" { headers["Content-Length"] = String(ObservationHistoryPage.maximumPageBytes + 1) }
        register(fixture, data: data, headers: headers)
        await #expect(throws: (any Error).self) {
            try await read(fixture, response: { if kind == "scope" { throw MerianError.invalidResponse } })
        }
    }

    @Test func staleClaimAndChangedAccountDenyBeforeRead() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        fixture.mock.register(path: Self.path) { _ in Issue.record("Stale read"); throw MerianError.invalidResponse }
        fixture.dispatcher.overridingAuthUserID = UUID()
        await #expect(throws: (any Error).self) { try await read(fixture) }
        fixture.dispatcher.overridingAuthUserID = fixture.seed.source.ownerID
        try Store.hold(fixture.permit.claim, proof: fixture.seed.proof, container: fixture.seed.container, isCurrent: { true })
        await #expect(throws: (any Error).self) { try await read(fixture) }
    }

    @Test func unconsumedClaimCannotEnterRecovery() async throws {
        let seed = try await ObservationAudioExecutionStoreTests().ready()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let claim = try Store.claim(ObservationAudioExecutionStoreTests().bind(seed), purpose: .initial,
            proof: seed.proof, container: seed.container, isCurrent: { true })
        let fixture = try await Fixture(); defer { fixture.close() }
        fixture.mock.register(path: Self.path) { _ in Issue.record("Unconsumed read"); throw MerianError.invalidResponse }
        await #expect(throws: (any Error).self) {
            try await transport(fixture).read(claim, validateAttempt: { Issue.record("Unexpected admission") }, validateResponse: {})
        }
    }

    @Test func recoveryGenerationReadsWithoutGrantingAnotherDispatch() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let proof = try fixture.seed.proof
        try Store.hold(fixture.permit.claim, proof: proof, container: fixture.seed.container, isCurrent: { true })
        let claim = try Store.claim(Store.read(proof, container: fixture.seed.container, isCurrent: { true }), purpose: .recovery,
            proof: proof, container: fixture.seed.container, isCurrent: { true })
        register(fixture, data: try envelope(fixture))
        let bytes = try await transport(fixture).read(claim, validateAttempt: {
            try Store.validate(claim, proof: proof, container: fixture.seed.container, isCurrent: { true })
        }, validateResponse: {})
        #expect(bytes != nil)
        #expect(throws: (any Error).self) {
            try Store.consume(claim, proof: proof, container: fixture.seed.container, isCurrent: { true })
        }
        #expect(try Store.read(proof, container: fixture.seed.container, isCurrent: { true }).work == claim.snapshot.work)
    }

    @Test func accountLossDuringReadWithholdsKnownBytes() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let data = try envelope(fixture)
        fixture.mock.register(path: Self.path) { wire in
            fixture.dispatcher.overridingAuthUserID = UUID()
            return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        await #expect(throws: (any Error).self) { try await read(fixture) }
    }

    @Test func replacedClaimAfterReplyCannotSettle() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        let proof = try fixture.seed.proof
        register(fixture, data: try envelope(fixture))
        let bytes = try await read(fixture, response: {
            try Store.hold(fixture.permit.claim, proof: proof, container: fixture.seed.container, isCurrent: { true })
        })
        let result = try #require(bytes)
        #expect(throws: (any Error).self) {
            try Store.complete(fixture.permit.claim, resultBytes: result, proof: proof, container: fixture.seed.container, isCurrent: { true })
        }
    }

    @Test func knownOutcomeSettlesAfterCancellationAndNeverSelectsTheChild() async throws {
        let fixture = try await Fixture(); defer { fixture.close() }
        register(fixture, data: try envelope(fixture))
        let proof = try fixture.seed.proof
        let task = Task {
            let received = try await read(fixture, response: { withUnsafeCurrentTask { $0?.cancel() } })
            let bytes = try #require(received)
            return try Store.complete(fixture.permit.claim, resultBytes: bytes, proof: proof,
                container: fixture.seed.container, isCurrent: { true })
        }
        #expect(try await task.value.childID == fixture.seed.preparation.identity.analysisID)
        let parent = try #require(ModelContext(fixture.seed.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(parent.selectedAnalysisID == fixture.seed.source.analysisID.uuidString.lowercased())
    }
}
