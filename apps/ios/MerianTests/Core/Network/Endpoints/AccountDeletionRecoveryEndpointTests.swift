import Foundation
import Testing

@testable import Merian

@Suite("Account Deletion Recovery Endpoints")
@MainActor
struct AccountDeletionRecoveryEndpointTests {
    @Test func testPreparedDeletionRecoverySeparatesRecoveryAndAcknowledgementProofs() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let recovery = String(repeating: "S", count: 43)
        let acknowledgement = String(repeating: "T", count: 43)
        let expiry = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(24 * 60 * 60)
        )
        var expectedOperation = "recover"
        fixture.transport.register(path: "/recover-account-deletion") { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["protocol_version"] as? Int == 2)
            #expect(payload["operation"] as? String == expectedOperation)
            if expectedOperation == "recover" {
                #expect(payload["recovery_capability"] as? String == recovery)
                #expect(payload["acknowledgement_capability"] == nil)
                return (
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(
                        """
                        {"success":true,"status":"not_committed","protocol_version":2,"manual_provider_revocation_required":false,"recovery_capability_expires_at":"\(expiry)","recovery_acknowledged":false}
                        """.utf8
                    )
                )
            }
            #expect(
                payload["acknowledgement_capability"] as? String
                    == acknowledgement
            )
            #expect(payload["recovery_capability"] == nil)
            return (
                HTTPURLResponse(
                    url: URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {"success":true,"status":"completed","protocol_version":2,"manual_provider_revocation_required":false,"recovery_capability_expires_at":"\(expiry)","recovery_acknowledged":true}
                    """.utf8
                )
            )
        }

        let uncommitted = try await fixture.client
            .recoverPreparedAccountDeletionV2(
                recoveryCapability: recovery
            )
        #expect(uncommitted.status == .notCommitted)
        expectedOperation = "acknowledge"
        let acknowledged = try await fixture.client
            .acknowledgeAccountDeletionRecoveryV2(
                acknowledgementCapability: acknowledgement
            )
        #expect(acknowledged.recoveryAcknowledged == true)
    }

    @Test func testAccountDeletionRecoveryUsesOnlyPublicCapability() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let capability = String(repeating: "B", count: 43)
        let expiry = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(24 * 60 * 60)
        )
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        fixture.transport.register(path: "/recover-account-deletion") { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "apikey") != nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload.count == 2)
            #expect(payload["operation"] as? String == "acknowledge")
            #expect(payload["recovery_capability"] as? String == capability)
            return (
                mockResponse,
                Data(
                    """
                    {"success":true,"status":"completed","manual_provider_revocation_required":true,"recovery_capability_expires_at":"\(expiry)","recovery_acknowledged":true}
                    """.utf8
                )
            )
        }

        let receipt = try await fixture.client
            .recoverAcceptedAccountDeletion(
                recoveryCapability: capability,
                acknowledge: true
            )

        #expect(receipt.status == .completed)
        #expect(receipt.manualProviderRevocationRequired)
        #expect(receipt.recoveryAcknowledged == true)
    }

    @Test func testAcknowledgedDeletionRecoveryRemainsReplayableAfterExpiry() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let capability = String(repeating: "C", count: 43)
        let expiredAt = "2025-01-01T00:00:00Z"
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        fixture.transport.register(path: "/recover-account-deletion") { _ in
            (
                mockResponse,
                Data(
                    """
                    {"success":true,"status":"completed","manual_provider_revocation_required":false,"recovery_capability_expires_at":"\(expiredAt)","recovery_acknowledged":true}
                    """.utf8
                )
            )
        }

        let receipt = try await fixture.client
            .recoverAcceptedAccountDeletion(
                recoveryCapability: capability,
                acknowledge: false
            )

        #expect(receipt.recoveryAcknowledged == true)
        #expect(receipt.recoveryCapabilityExpiresAt == expiredAt)
    }

    @Test func testAccountDeletionRecoveryRejectsMalformedCapabilityBeforeIO() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        var invoked = false
        fixture.transport.register(path: "/recover-account-deletion") { _ in
            invoked = true
            throw URLError(.badServerResponse)
        }

        await #expect(throws: MerianError.invalidResponse) {
            _ = try await fixture.client
                .recoverAcceptedAccountDeletion(
                    recoveryCapability: "not-a-capability",
                    acknowledge: false
                )
        }
        #expect(!invoked)
    }
}
