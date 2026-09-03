import Foundation
import Testing

@testable import Merian

enum NetworkEndpointTestSupport {
    /// Reads a potentially one-shot body stream once, then shares the same bytes
    /// with payload assertions and exact-wire replay comparisons.
    @discardableResult
    static func expectPOST(
        _ request: URLRequest,
        function: String,
        json: String,
        timeout: TimeInterval = 30,
        idempotencyKey: String? = nil
    ) throws -> NetworkEndpointRequestSnapshot {
        #expect(request.url?.scheme == "https")
        #expect(request.url?.path == "/functions/v1/\(function)")
        #expect(request.url?.query == nil)
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == timeout)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Merian-Entitlement-Protocol") == "3")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == idempotencyKey)
        let body = try #require(MockURLProtocol.bodyData(for: request))
        #expect(try canonicalRequestJSON(body) == canonicalRequestJSON(Data(json.utf8)))
        return NetworkEndpointRequestSnapshot(
            body: body,
            idempotencyKey: request.value(forHTTPHeaderField: "Idempotency-Key"),
            timeout: request.timeoutInterval
        )
    }

    static func canonicalRequestJSON(_ data: Data) throws -> Data {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // NSDictionary/NSNumber equality conflates JSON Booleans with 0 and 1.
        // Sorted serialization ignores key order while retaining wire scalar types.
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func response(
        to request: URLRequest,
        status: Int = 200,
        json: String
    ) throws -> (HTTPURLResponse, Data) {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "X-Merian-Handler": "1"]
        ))
        return (response, Data(json.utf8))
    }
}

struct NetworkEndpointRequestSnapshot: Equatable, Sendable {
    let body: Data
    let idempotencyKey: String?
    let timeout: TimeInterval
}

/// A private client and scoped transport per test; never changes the shared client.
@MainActor
struct NetworkEndpointFixture {
    let client = MerianNetworkClient()
    let transport = ScopedMockTransport()
    let session: URLSession

    init() {
        session = transport.makeSession()
        client.overridingSession = session
        client.overridingAuthUserID = UUID()
    }

    func close() {
        session.invalidateAndCancel()
    }
}
