import Foundation
import os
import Testing

@testable import Merian

@Suite("Enrichment, Export, and Feedback Transport")
@MainActor
struct EnrichmentExportFeedbackTransportTests {
    typealias RequestCase = EnrichmentExportFeedbackRequestCase

    @Test(
        arguments: [RequestCase.Kind.deferredContext, .export, .survey, .communityFeedback],
        ["", "not-json", "null", "[]", "{}", #"{"success":false}"#]
    )
    func bodyIgnoringOperationsDoNotDecodeSuccess(kind: RequestCase.Kind, json: String) async throws {
        let testCase = try RequestCase.make(kind)
        try await testCase.withResponse(json) { client in try await testCase.invoke(client) }
    }

    @Test(
        arguments: [RequestCase.Kind.deferredContext, .export, .survey, .communityFeedback],
        [201, 202, 204, 299]
    )
    func bodyIgnoringOperationsKeepAll2xxStatuses(kind: RequestCase.Kind, status: Int) async throws {
        let testCase = try RequestCase.make(kind)
        try await testCase.withResponse("", status: status) { client in try await testCase.invoke(client) }
    }

    @Test(arguments: RequestCase.Kind.allCases, [400, 401, 403, 404, 409, 422])
    func handlerDenialsDoNotDecodeSuccessOrRefreshAuth(kind: RequestCase.Kind, status: Int) async throws {
        let testCase = try RequestCase.make(kind)
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            return true
        }
        await confirmation("One handler denial") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: RequestCase.responseJSON)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("A handler denial must not become success")
            } catch MerianError.httpError(let actualStatus, _) {
                #expect(status != 401 && actualStatus == status)
            } catch MerianError.invalidResponse {
                #expect(status == 401)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(refreshes.withLock { $0 } == 0)
    }

    @Test(arguments: RequestCase.Kind.allCases, [200, 401, 503])
    func classifiedAuthRefreshKeepsOneReplayAndTheSameBody(kind: RequestCase.Kind, replayStatus: Int) async throws {
        let testCase = try RequestCase.make(kind)
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        await confirmation("One session refresh") { refreshed in
            fixture.client.overridingAuthSessionRefresh = {
                refreshed()
                return true
            }
            fixture.transport.register(path: testCase.path) { request in
                let snapshot = try testCase.expectRequest(request)
                requests.withLock { $0.append(snapshot) }
                let attempt = attempts.withLock { count in count += 1; return count }
                if attempt == 1 || (attempt == 2 && replayStatus == 401) {
                    return try NetworkEndpointTestSupport.response(
                        to: request, status: 401,
                        json: #"{"code":"invalid_session_token","error":"Synthetic invalid session"}"#
                    )
                }
                return try NetworkEndpointTestSupport.response(
                    to: request, status: attempt == 2 ? replayStatus : 200, json: RequestCase.responseJSON
                )
            }
            do {
                try await testCase.invoke(fixture.client)
                #expect(replayStatus == 200)
            } catch MerianError.httpError(let status, _) {
                #expect(replayStatus != 200 && status == replayStatus)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(requests.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: EnrichmentEndpointReplayScenario.allCases)
    func keyedEnrichmentKeepsBoundedAmbiguousReplay(scenario: EnrichmentEndpointReplayScenario) async throws {
        let testCase = try RequestCase.make(.enrichment)
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        fixture.transport.register(path: testCase.path) { request in
            let snapshot = try testCase.expectRequest(request)
            requests.withLock { $0.append(snapshot) }
            let attempt = attempts.withLock { count in count += 1; return count }
            if attempt == 1 || (attempt == 2 && !scenario.replaySucceeds) {
                if !scenario.isServerFailure { throw URLError(.networkConnectionLost) }
                return try NetworkEndpointTestSupport.response(to: request, status: 503, json: RequestCase.responseJSON)
            }
            return try NetworkEndpointTestSupport.response(to: request, json: RequestCase.responseJSON)
        }
        do {
            try await testCase.invoke(fixture.client)
            #expect(scenario.replaySucceeds)
        } catch MerianError.httpError(let status, _) {
            #expect(!scenario.replaySucceeds && scenario.isServerFailure && status == 503)
        } catch let error as URLError {
            #expect(!scenario.replaySucceeds && !scenario.isServerFailure && error.code == .networkConnectionLost)
        } catch {
            Issue.record("Unexpected error type: \(type(of: error))")
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(requests.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: [RequestCase.Kind.deferredContext, .export, .survey, .communityFeedback], [false, true])
    func unkeyedMutationsNeverReplayAmbiguousFailures(kind: RequestCase.Kind, serverFailure: Bool) async throws {
        let testCase = try RequestCase.make(kind)
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One unkeyed mutation attempt") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                if serverFailure {
                    return try NetworkEndpointTestSupport.response(to: request, status: 503, json: RequestCase.responseJSON)
                }
                throw URLError(.networkConnectionLost)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("An unkeyed mutation must propagate an ambiguous failure")
            } catch MerianError.httpError(let status, _) {
                #expect(serverFailure && status == 503)
            } catch let error as URLError {
                #expect(!serverFailure && error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test(arguments: RequestCase.Kind.allCases)
    func cancellationBeforeDispatchDoesNotSend(kind: RequestCase.Kind) async throws {
        let testCase = try RequestCase.make(kind)
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No cancelled request", expectedCount: 0) { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: RequestCase.responseJSON)
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                try await testCase.invoke(fixture.client)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test(arguments: RequestCase.Kind.allCases)
    func independentlyCancelledTransportKeepsItsError(kind: RequestCase.Kind) async throws {
        let testCase = try RequestCase.make(kind)
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One independently cancelled transport") { sent in
            fixture.transport.register(path: testCase.path) { _ in
                sent()
                throw URLError(.cancelled)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("Transport cancellation must propagate")
            } catch let error as URLError {
                #expect(error.code == .cancelled)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test func preparedJSONBridgeForwardsExactBytesTimeoutAndKey() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let json = "{ \"scope\" : \"enrichment\", \"scan_id\" : \"\(RequestCase.scanID)\" }\n"
        try await confirmation("One prepared-body request") { sent in
            fixture.transport.register(path: "/enrich-scan") { request in
                sent()
                let snapshot = try NetworkEndpointTestSupport.expectPOST(
                    request, function: "enrich-scan", json: json, timeout: 17,
                    idempotencyKey: RequestCase.scanID.lowercased()
                )
                #expect(snapshot.body == Data(json.utf8))
                return try NetworkEndpointTestSupport.response(to: request, json: "raw-response")
            }
            let data = try await fixture.client.performAuthenticatedPreparedJSONPost(
                function: "enrich-scan", body: Data(json.utf8), timeoutInterval: 17,
                idempotencyKey: RequestCase.scanID.lowercased()
            )
            #expect(data == Data("raw-response".utf8))
        }
    }
}

enum EnrichmentEndpointReplayScenario: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case transportRecovers, transportExhausts, serverRecovers, serverExhausts
    var testDescription: String { rawValue }
    var isServerFailure: Bool { self == .serverRecovers || self == .serverExhausts }
    var replaySucceeds: Bool { self == .transportRecovers || self == .serverRecovers }
}
