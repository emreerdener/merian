import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationSourceTransportTests {
    typealias Values = ObservationSourceReservationTests
    static let path = "/reserve-observation-analysis-source"

    @MainActor struct Fixture {
        let mock = ScopedMockTransport()
        let pinned = PinnedNetworkTransport()
        let session: URLSession
        let dispatcher: AuthenticatedTransportDispatcher
        let candidate: ObservationSourceReservationRequest
        var transport: ObservationSourceReservationTransport { .init(baseURL: "https://example.supabase.co", dispatcher: dispatcher) }
        init() throws {
            candidate = try Values.candidate()
            session = mock.makeSession(); pinned.overridingSession = session
            dispatcher = AuthenticatedTransportDispatcher(sessionTransport: pinned)
            dispatcher.overridingAuthUserID = Values.owner
        }
        func close() { session.invalidateAndCancel() }
        func send(attempt: @escaping @MainActor @Sendable () throws -> Void = {},
                  response: @escaping @MainActor @Sendable () throws -> Void = {}) async throws -> ObservationSourceReservationReply {
            try await transport.reserve(candidate, ownerID: Values.owner, validateAttempt: attempt, validateResponse: response)
        }
        func receipt(_ state: String = "reserved") throws -> Data {
            try JSONSerialization.data(withJSONObject: Values.receipt(candidate, state: state))
        }
    }

    @Test(arguments: ["reserved", "held", "unavailable"])
    func fixedRouteUsesExactCandidateAndNoExecutionHeaders(state: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let data = try fixture.receipt(state), body = fixture.candidate.body
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.mock.register(path: Self.path) { wire in
            calls.withLock { $0 += 1 }
            #expect(wire.httpMethod == "POST" && wire.timeoutInterval == 5)
            #expect(MockURLProtocol.bodyData(for: wire) == body)
            #expect(wire.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(wire.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            #expect(wire.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        var attempts = 0, responses = 0
        #expect(try await fixture.send(attempt: { attempts += 1 }, response: { responses += 1 }).data == data)
        #expect(calls.withLock { $0 } == 1 && attempts == 1 && responses == 1)
        #expect(PinnedNetworkTransport.makeConfiguration().timeoutIntervalForResource == 90)
    }

    @Test(arguments: [401, 404, 409, 429, 503, -1])
    func errorsNeverRetryOrBecomeObservations(status: Int) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let data = try fixture.receipt("unavailable"), calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Unexpected Auth retry"); return true }
        fixture.mock.register(path: Self.path) { wire in
            calls.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        await #expect(throws: (any Error).self) { try await fixture.send() }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: ["owner", "claim"])
    func staleScopeCannotSend(kind: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        fixture.mock.register(path: Self.path) { _ in Issue.record("Stale attempt sent bytes"); throw MerianError.invalidResponse }
        if kind == "owner" { fixture.dispatcher.overridingAuthUserID = UUID() }
        await #expect(throws: (any Error).self) {
            try await fixture.send(attempt: { if kind == "claim" { throw MerianError.invalidResponse } })
        }
    }

    @Test(arguments: ["exact", "code", "extra", "request", "message", "mime", "scope"])
    func onlyExactConflictPreservesDefiniteScopedOutcome(kind: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        var row: [String: Any] = ["error": "Source reservation is unavailable.",
            "code": "analysis_history_operation_conflict", "request_id": UUID().uuidString.lowercased()]
        if kind == "code" { row["code"] = "analysis_history_unavailable" }
        if kind == "extra" { row["receipt"] = "reserved" }
        if kind == "request" { row["request_id"] = "invalid" }
        if kind == "message" { row["error"] = "" }
        let data = try JSONSerialization.data(withJSONObject: row)
        fixture.mock.register(path: Self.path) { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 409, httpVersion: nil,
                headerFields: ["Content-Type": kind == "mime" ? "text/plain" : "application/json"])!, data)
        }
        do {
            _ = try await fixture.send(response: { if kind == "scope" { throw MerianError.invalidResponse } })
            Issue.record("Conflict unexpectedly returned a receipt")
        } catch let conflict as ObservationSourceReservationConflict {
            #expect(kind == "exact")
            #expect(conflict.request == fixture.candidate && conflict.ownerID == Values.owner)
        } catch { #expect(kind != "exact") }
    }

    @Test(arguments: ["actual", "declared", "mime", "scope", "identity"])
    func boundedReplyRequiresExactResponseScope(kind: String) async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        var row = Values.receipt(fixture.candidate)
        if kind == "identity" { row["owner_id"] = UUID().uuidString.lowercased() }
        let data = kind == "actual" ? Data(repeating: 32, count: 2_049) : try JSONSerialization.data(withJSONObject: row)
        var headers = ["Content-Type": kind == "mime" ? "text/plain" : "application/json"]
        if kind == "declared" { headers["Content-Length"] = "2049" }
        let frozenHeaders = headers
        fixture.mock.register(path: Self.path) { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil, headerFields: frozenHeaders)!, data)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.send(response: { if kind == "scope" { throw MerianError.invalidResponse } })
        }
    }

    @Test func exactKnownReplySurvivesDispatchCancellationButNotSettlementLoss() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let data = try fixture.receipt()
        fixture.mock.register(path: Self.path) { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, data)
        }
        let task = Task { @MainActor in
            try await fixture.send(response: { withUnsafeCurrentTask { $0?.cancel() } })
        }
        #expect(try await task.value.data == data)
        await #expect(throws: (any Error).self) {
            try await fixture.send(response: { throw SupabaseAuthTransitionError.signOutSessionChanged })
        }
    }
}
