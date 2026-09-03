import Foundation
import os
import Testing

@testable import Merian

@Suite("Species Dictionary Network Transport")
@MainActor
struct SpeciesDictionaryNetworkTransportTests {
    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations, ["", "not-json", "{}", #"{"data":null}"#])
    func malformedSuccessKeepsRawDecodingErrors(_ testCase: SpeciesDictionaryNetworkRequestCase, json: String) async throws {
        try await testCase.withResponse(json) { client in
            await #expect(throws: DecodingError.self) { try await testCase.invoke(client) }
        }
    }

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations, [400, 401, 403, 404, 409, 422])
    func handlerDenialsNeverBecomeSuccessOrRefreshAuth(_ testCase: SpeciesDictionaryNetworkRequestCase, status: Int) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            // Keep an unexpected recovery inside the mock transport.
            return true
        }
        await confirmation("One handler denial") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: testCase.responseJSON)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("A handler denial must not be decoded as success")
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

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations, [200, 401, 503])
    func authRefreshKeepsOneReplayAndIdenticalRequest(
        _ testCase: SpeciesDictionaryNetworkRequestCase, replayStatus: Int
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [SpeciesDictionaryRequestSnapshot]())
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
                        to: request, status: 401, json: #"{"code":"invalid_session_token","error":"Invalid session"}"#
                    )
                }
                return try NetworkEndpointTestSupport.response(
                    to: request, status: attempt == 2 ? replayStatus : 200, json: testCase.responseJSON
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

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations, SpeciesDictionaryReplayScenario.allCases)
    func safeReadsKeepBoundedAmbiguousReplay(
        _ testCase: SpeciesDictionaryNetworkRequestCase, scenario: SpeciesDictionaryReplayScenario
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [SpeciesDictionaryRequestSnapshot]())
        fixture.transport.register(path: testCase.path) { request in
            let snapshot = try testCase.expectRequest(request)
            requests.withLock { $0.append(snapshot) }
            let attempt = attempts.withLock { count in count += 1; return count }
            if attempt == 1 || (attempt == 2 && !scenario.replaySucceeds) {
                if !scenario.isServerFailure { throw URLError(.networkConnectionLost) }
                return try NetworkEndpointTestSupport.response(to: request, status: 503, json: testCase.responseJSON)
            }
            return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
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

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations)
    func cancellationBeforeDispatchDoesNotSend(_ testCase: SpeciesDictionaryNetworkRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No cancelled cold-cache request", expectedCount: 0) { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                try await testCase.invoke(fixture.client)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations)
    func independentlyCancelledTransportKeepsItsError(_ testCase: SpeciesDictionaryNetworkRequestCase) async {
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

    @Test func independentOverviewRequestsReceiveDifferentCacheBusters() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let requests = OSAllocatedUnfairLock(initialState: [SpeciesDictionaryRequestSnapshot]())
        let testCase = SpeciesDictionaryNetworkRequestCase.overview
        try await confirmation("Two independent overview requests", expectedCount: 2) { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                let snapshot = try testCase.expectRequest(request)
                requests.withLock { $0.append(snapshot) }
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            try await testCase.invoke(fixture.client)
            try await testCase.invoke(fixture.client)
        }
        #expect(requests.withLock { $0.count == 2 && $0[0].transport.body != $0[1].transport.body })
    }
}

enum SpeciesDictionaryReplayScenario: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case transportRecovers, transportExhausts, serverRecovers, serverExhausts
    var testDescription: String { rawValue }
    var isServerFailure: Bool { self == .serverRecovers || self == .serverExhausts }
    var replaySucceeds: Bool { self == .transportRecovers || self == .serverRecovers }
}
