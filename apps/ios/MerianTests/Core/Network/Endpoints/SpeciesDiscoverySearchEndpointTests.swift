import Foundation
import Testing
@testable import Merian

@Suite("Species Discovery Search Endpoint")
@MainActor
struct SpeciesDiscoverySearchEndpointTests {
    @Test func searchUsesTypedAuthenticatedTransportAndRejectsDifferentRequest() async throws {
        let transport = ScopedMockTransport()
        let client = MerianNetworkClient()
        client.overridingSession = transport.makeSession()
        client.overridingAuthUserID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        let id = "00000000-0000-4000-8000-000000000001"
        transport.register(path: "/species-discovery-search") { request in
            #expect(request.httpMethod == "POST")
            let data = try #require(MockURLProtocol.bodyData(for: request))
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["request_id"] as? String == id)
            #expect(body["question"] as? String == "Only butterflies")
            #expect(body["result_kind"] as? String == "species")
            #expect(body["user_id"] == nil)
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data("""
            {"schema_version":1,"request_id":"00000000-0000-4000-8000-000000000002",
            "result_kind":"species","status":"results","message":"Butterflies",
            "context":{"query":"butterfly","group":"insects","media":null,"mode":"description"},
            "species":[],"sightings":[],"next_cursor":null}
            """.utf8))
        }
        do {
            _ = try await client.searchSpecies(.init(requestId: id, question: "Only butterflies", context: nil, resultKind: .species, cursor: nil))
            Issue.record("A mismatched request identity was accepted")
        } catch {
            #expect(error as? MerianError == .invalidResponse)
        }
    }
}
