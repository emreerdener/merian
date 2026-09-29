import Foundation
import os
import Testing
@testable import Merian

@MainActor
struct VerifiedSpeciesReviewEndpointTests {
    @Test func exactRouteReturnsBoundedTypedAcknowledgement() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let receipt: [String: Any] = ["schema_version": 1, "scan_id": VerifiedReviewFixtures.scanID,
                                      "review": VerifiedReviewFixtures.review(1, name: nil)]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: receipt), as: UTF8.self)
        fixture.transport.register(path: "/confirm-scan-species") { request in
            try NetworkEndpointTestSupport.expectPOST(request, function: "confirm-scan-species", json:
                #"{"scan_id":"10000000-0000-4000-8000-000000000001","expected_revision":0,"action":"clear"}"#)
            return try NetworkEndpointTestSupport.response(to: request, json: json)
        }
        let request = try VerifiedSpeciesReviewRequest(mutation: .reset(scanID: VerifiedReviewFixtures.scanID),
            revision: 0, primary: VerifiedReviewFixtures.primary())
        let result = try await fixture.client.confirmScanSpecies(request)
        #expect(result.review.revision == 1 && result.review.identity == nil)
    }

    @Test(arguments: [401, 409, 503])
    func failuresAreNotAutomaticallyReplayedOrSentToSessionRecovery(status: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        fixture.transport.register(path: "/confirm-scan-species") { request in
            attempts.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: request, status: status,
                json: status == 401 ? #"{"code":"invalid_session_token"}"# : #"{"code":"species_review_revision_conflict"}"#)
        }
        let request = try VerifiedSpeciesReviewRequest(mutation: .reset(scanID: VerifiedReviewFixtures.scanID),
            revision: 0, primary: VerifiedReviewFixtures.primary())
        await #expect(throws: Error.self) { try await fixture.client.confirmScanSpecies(request) }
        #expect(attempts.withLock { $0 } == 1 && refreshes.withLock { $0 } == 0)
    }
}
