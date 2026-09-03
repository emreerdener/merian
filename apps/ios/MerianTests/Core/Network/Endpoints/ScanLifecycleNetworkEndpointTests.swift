import Foundation
import Testing

@testable import Merian

@Suite("Scan Lifecycle Network Requests")
@MainActor
struct ScanLifecycleNetworkEndpointTests {
    private typealias Fixtures = ScanLifecycleNetworkFixtures

    @Test(arguments: ScanLifecycleNetworkRequestCase.all)
    func requestVariantsKeepTheirWireShape(_ testCase: ScanLifecycleNetworkRequestCase) async throws {
        try await testCase.withResponse { client in try await testCase.invoke(client) }
    }

    @Test func bulkProjectionKeepsRawCallerKeysAndIgnoresRowOrder() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("One two-scan probe") { sent in
            fixture.transport.register(path: "/check-scan-status") { request in
                sent()
                #expect(request.httpMethod == "POST" && request.timeoutInterval == 30)
                #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
                let body = try #require(MockURLProtocol.bodyData(for: request))
                let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(Set(payload.keys) == ["scans"])
                let rows = try #require(payload["scans"] as? [[String: Any]])
                #expect(rows.count == 2)
                let actual = try rows.map { row in
                    try NetworkEndpointTestSupport.canonicalRequestJSON(JSONSerialization.data(withJSONObject: row))
                }
                let expected = try [#"{"scan_id":" Scan-A ","required_video_count":2}"#, #"{"scan_id":"Scan-B"}"#].map {
                    try NetworkEndpointTestSupport.canonicalRequestJSON(Data($0.utf8))
                }
                #expect(Set(actual) == Set(expected))
                return try NetworkEndpointTestSupport.response(to: request, json: """
                {"results":[
                  {"scan_id":" scan-b ","status":"not_found","complimentary_state":"held"},
                  {"scan_id":"SCAN-A","status":"found","complimentary_state":"consumed"}
                ]}
                """)
            }
            let results = try await fixture.client.checkScanStatuses([" Scan-A ": 2, "Scan-B": -3])
            #expect(Set(results.keys) == [" Scan-A ", "Scan-B"])
            #expect(results[" Scan-A "]?.scanId == "SCAN-A")
            #expect(results[" Scan-A "]?.complimentaryState == .consumed)
            #expect(results["Scan-B"]?.status == .notFound)
            #expect(results["Scan-B"]?.complimentaryState == .held)
        }
    }

    @Test func emptyBulkReturnsBeforeAuthOrTaskCancellation() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        try await confirmation("Empty bulk never dispatches", expectedCount: 0) { sent in
            fixture.transport.register(path: "/check-scan-status") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: #"{"results":[]}"#)
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await fixture.client.checkScanStatuses([:])
            }
            let results = try await task.value
            #expect(results.isEmpty)
        }
    }

    @Test func invalidBulkAliasesFailBeforeAuthOrDispatch() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        await confirmation("Invalid bulk never dispatches", expectedCount: 0) { sent in
            fixture.transport.register(path: "/check-scan-status") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "{}")
            }
            for requirements in [["": 0], [" \n\t ": 0], ["SCAN-A": 0, " scan-a ": 1]] {
                let task = Task { @MainActor in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return try await fixture.client.checkScanStatuses(requirements)
                }
                await #expect(throws: MerianError.invalidResponse) { try await task.value }
            }
        }
    }

    @Test func recoveryEncodingFailureIsNotRemappedOrDispatched() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        await confirmation("Invalid recovery never dispatches", expectedCount: 0) { sent in
            fixture.transport.register(path: "/check-scan-status") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: Fixtures.statusJSON)
            }
            await #expect(throws: EncodingError.self) {
                try await fixture.client.checkScanStatusDetails(
                    scanId: Fixtures.scanID, recoveryScan: Fixtures.recoveryScan(confidence: .nan)
                )
            }
        }
    }
}
