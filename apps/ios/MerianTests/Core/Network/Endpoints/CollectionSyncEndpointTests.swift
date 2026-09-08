import Foundation
import os
import Testing

@testable import Merian

@Suite("Collection Sync Endpoint")
@MainActor
struct CollectionSyncEndpointTests {
    @Test func testSyncCollectionPayloadEncoding() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/sync-collections") { request in
            try NetworkEndpointTestSupport.expectPOST(
                request,
                function: "sync-collections",
                json: """
                {"collections":[{"id":"collection-a","name":"Field Notes",
                "created_at":"2026-03-25T13:40:03Z","is_deleted":false,
                "scan_ids":["scan-a","scan-b"]}]}
                """
            )
            return try NetworkEndpointTestSupport.response(
                to: request,
                json: "not-json"
            )
        }
        let createdAt = try #require(
            DateUtilities.iso8601Formatter.date(
                from: "2026-03-25T13:40:03Z"
            )
        )

        try await fixture.client.syncCollections([
            CollectionSyncSnapshot(
                id: "collection-a",
                name: "Field Notes",
                createdAt: createdAt,
                isPendingDeletion: false,
                scanIDs: ["scan-a", "scan-b"]
            )
        ])
    }

    @Test func classifiedUnauthorizedDefersRecoveryToDurableRetryOwner()
        async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            return true
        }
        fixture.transport.register(path: "/sync-collections") { request in
            attempts.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(
                to: request,
                status: 401,
                json: #"{"code":"invalid_session_token"}"#
            )
        }

        do {
            try await fixture.client.syncCollections([])
            Issue.record("Expected unauthorized collection sync to fail")
        } catch MerianError.httpError(let statusCode, _) {
            #expect(statusCode == 401)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(attempts.withLock { $0 } == 1)
        #expect(refreshes.withLock { $0 } == 0)
    }
}
