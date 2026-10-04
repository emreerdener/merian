import Foundation
import os
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

    @Test func testHistoryRefusalPreservesStableCodeAndDoesNotReplay() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One refused legacy deletion") { sent in
            fixture.transport.register(path: "/delete-scan") { request in
                sent()
                return try NetworkEndpointTestSupport.response(
                    to: request, status: 409,
                    json: #"{"error":"Update Merian to review and delete this saved scan.","code":"legacy_observation_delete_requires_upgrade"}"#
                )
            }
            do {
                try await fixture.client.deleteScan(scanId: "00000000-0000-4000-8000-00000000d203")
                Issue.record("Refused deletion must not become success")
            } catch {
                #expect(OfflineQueueManager.cloudDeletionRequiresHistoryReview(error: error))
                #expect(!OfflineQueueManager.cloudDeletionWasConfirmed(error: error))
            }
        }
    }

    @Test func accountBoundDeletionReturnsUnauthorizedWithoutRefreshingItsOwnLease() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            return true
        }
        fixture.transport.register(path: "/delete-scan") { request in
            attempts.withLock { $0 += 1 }
            try NetworkEndpointTestSupport.expectPOST(request, function: "delete-scan",
                json: #"{"scanId":"00000000-0000-4000-8000-00000000d311"}"#)
            return try NetworkEndpointTestSupport.response(to: request, status: 401,
                json: #"{"code":"invalid_session_token","error":"Synthetic invalid session"}"#)
        }
        do {
            try await fixture.client.deleteScan(scanId: "00000000-0000-4000-8000-00000000d311", expectedOwnerID: owner)
            Issue.record("Unauthorized deletion must remain retryable")
        } catch MerianError.httpError(let status, _) {
            #expect(status == 401)
        }
        #expect(attempts.withLock { $0 } == 1)
        #expect(refreshes.withLock { $0 } == 0)
    }

}
