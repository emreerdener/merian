import Foundation
import Testing

@Suite("Network Endpoint Test Support")
struct NetworkEndpointTestSupportTests {
    private let key = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private let wireJSON = "{ \"action\": \"send\", \"enabled\": true }\n"
    private let reorderedJSON = #"{"enabled":true,"action":"send"}"#

    @Test(arguments: [false, true])
    func validatedSnapshotRetainsExactBytesKeyAndTimeout(streamed: Bool) throws {
        let request = try request(json: wireJSON, streamed: streamed, key: key, timeout: 45)
        let snapshot = try NetworkEndpointTestSupport.expectPOST(
            request, function: "test-endpoint", json: reorderedJSON, timeout: 45, idempotencyKey: key
        )

        // A second read from a closed httpBodyStream can return empty Data.
        // The snapshot must retain the bytes used for the successful assertion.
        #expect(snapshot.body == Data(wireJSON.utf8))
        #expect(snapshot.idempotencyKey == key)
        #expect(snapshot.timeout == 45)
    }

    @Test(arguments: [false, true])
    func replayComparisonDistinguishesReencodingFromExactBytes(streamed: Bool) throws {
        let first = try snapshot(json: wireJSON, streamed: streamed)
        let exactReplay = try snapshot(json: wireJSON, streamed: streamed)
        let reencodedReplay = try snapshot(json: reorderedJSON, streamed: streamed)

        #expect(first == exactReplay)
        #expect(first != reencodedReplay)
        #expect(first.body == Data(wireJSON.utf8))
        #expect(reencodedReplay.body == Data(reorderedJSON.utf8))
        #expect(
            try NetworkEndpointTestSupport.canonicalRequestJSON(first.body)
                == NetworkEndpointTestSupport.canonicalRequestJSON(reencodedReplay.body)
        )
    }

    @Test func replayComparisonAlsoRetainsKeyAndTimeoutIdentity() throws {
        let baseline = try snapshot(json: wireJSON, streamed: true)
        let keyedRequest = try request(json: wireJSON, streamed: true, key: key, timeout: 30)
        let keyed = try NetworkEndpointTestSupport.expectPOST(
            keyedRequest, function: "test-endpoint", json: reorderedJSON, idempotencyKey: key
        )
        let longerRequest = try request(json: wireJSON, streamed: true, timeout: 45)
        let longer = try NetworkEndpointTestSupport.expectPOST(
            longerRequest, function: "test-endpoint", json: reorderedJSON, timeout: 45
        )

        #expect(baseline.idempotencyKey == nil && baseline.timeout == 30)
        #expect(baseline.body == keyed.body && baseline.body == longer.body)
        #expect(baseline != keyed && baseline != longer)
    }

    @Test(arguments: [
        (#"{"value":true}"#, #"{"value":1}"#),
        (#"{"value":false}"#, #"{"value":0}"#),
        (#"{"value":1}"#, #"{"value":"1"}"#),
        (#"{"value":null}"#, #"{}"#)
    ])
    func payloadComparisonPreservesScalarTypesAndOmission(_ expected: String, _ actual: String) throws {
        #expect(
            try NetworkEndpointTestSupport.canonicalRequestJSON(Data(expected.utf8))
                != NetworkEndpointTestSupport.canonicalRequestJSON(Data(actual.utf8))
        )
    }

    @Test func payloadComparisonIgnoresObjectKeyOrderOnly() throws {
        #expect(
            try NetworkEndpointTestSupport.canonicalRequestJSON(Data(wireJSON.utf8))
                == NetworkEndpointTestSupport.canonicalRequestJSON(Data(reorderedJSON.utf8))
        )
    }

    private func snapshot(json: String, streamed: Bool) throws -> NetworkEndpointRequestSnapshot {
        try NetworkEndpointTestSupport.expectPOST(
            request(json: json, streamed: streamed), function: "test-endpoint", json: reorderedJSON
        )
    }

    private func request(
        json: String, streamed: Bool, key: String? = nil, timeout: TimeInterval = 30
    ) throws -> URLRequest {
        var request = URLRequest(
            url: try #require(URL(string: "https://network.example.test/functions/v1/test-endpoint")),
            timeoutInterval: timeout
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("3", forHTTPHeaderField: "X-Merian-Entitlement-Protocol")
        request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        if streamed {
            request.httpBodyStream = InputStream(data: Data(json.utf8))
        } else {
            request.httpBody = Data(json.utf8)
        }
        return request
    }
}
