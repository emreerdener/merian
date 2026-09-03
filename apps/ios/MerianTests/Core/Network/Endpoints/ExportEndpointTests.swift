import Foundation
import Testing

@testable import Merian

@Suite("Export Endpoints")
@MainActor
struct ExportEndpointTests {
    @Test(arguments: [nil, "personal", "user", "global", "", " Raw-Scope \n"] as [String?])
    func exportKeepsDefaultRawScopesPrecisionAndQueueTimeout(scope: String?) async throws {
        let testCase = try EnrichmentExportFeedbackRequestCase.make(.export, exportScope: scope)
        try await testCase.withResponse("") { client in try await testCase.invoke(client) }
    }

    @Test(arguments: [403, 429])
    func exportDoesNotHideReleaseOrRateDenials(status: Int) async throws {
        let testCase = try EnrichmentExportFeedbackRequestCase.make(.export)
        try await testCase.withResponse(
            #"{"code":"feature_unavailable","error":"Synthetic denial"}"#, status: status
        ) { client in
            do {
                try await testCase.invoke(client)
                Issue.record("A denied export must remain a failure")
            } catch MerianError.httpError(let actualStatus, _) {
                #expect(actualStatus == status)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test func testRequestDwcAExport() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        fixture.transport.register(path: "/request-export-dwca") { request in
            #expect(request.url?.path.hasSuffix("/request-export-dwca") == true)
            #expect(request.httpMethod == "POST")
            return (mockResponse, Data())
        }

        try await fixture.client.requestDwcAExport(scope: "user")
    }
}
