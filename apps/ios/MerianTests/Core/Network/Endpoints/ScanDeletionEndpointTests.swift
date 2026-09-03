import Foundation
import Testing

@testable import Merian

@Suite("Scan Deletion Endpoints")
@MainActor
struct ScanDeletionEndpointTests {
    @Test func testDeleteScanEndpoint() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        fixture.transport.register(path: "/delete-scan") { request in
            #expect(request.url?.path.hasSuffix("/delete-scan") == true)
            #expect(request.httpMethod == "POST")
            try NetworkEndpointTestSupport.expectPOST(
                request, function: "delete-scan",
                json: #"{"scanId":"019fad40-061e-7eb7-a896-996d93813d22"}"#
            )
            return (
                mockResponse,
                Data(#"{"success":true,"message":"Scan deleted."}"#.utf8)
            )
        }

        try await fixture.client.deleteScan(
            scanId: "019fad40-061e-7eb7-a896-996d93813d22"
        )
        // Success if no errors throw
    }

    @Test func testDeleteScanRejectsUnconfirmedSuccessResponse() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let invalidResponses = [
            Data(),
            Data(#"{"success":false}"#.utf8),
            Data(#"{"ok":true}"#.utf8),
            Data(#"[]"#.utf8)
        ]

        for invalidResponse in invalidResponses {
            fixture.transport.register(path: "/delete-scan") { _ in
                (mockResponse, invalidResponse)
            }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.deleteScan(
                    scanId: "019fad40-061e-7eb7-a896-996d93813d22"
                )
            }
        }
    }
}
