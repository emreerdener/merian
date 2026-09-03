import Foundation
import os
import Testing

@testable import Merian

@Suite("Account Deletion Endpoints")
@MainActor
struct AccountDeletionEndpointTests {
    @Test func testSafeDeleteAccountEndpoint() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let mockResponse = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 202, httpVersion: nil, headerFields: nil)!
        fixture.transport.register(path: "/safe-delete") { request in
            #expect(request.url?.path.hasSuffix("/safe-delete") == true)
            #expect(request.httpMethod == "POST")
            #expect(MockURLProtocol.bodyData(for: request) == nil)
            return (
                mockResponse,
                Data(
                    #"{"success":true,"status":"pending","manual_provider_revocation_required":true}"#.utf8
                )
            )
        }

        let receipt = try await fixture.client.safeDeleteAccount()
        #expect(receipt.status == .pending)
        #expect(receipt.manualProviderRevocationRequired)
    }

    @Test func testSafeDeleteBindsExactRecoveryCapability() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let capability = String(repeating: "A", count: 43)
        let expiry = "2099-02-09T12:34:56.123456+00:00"
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 202,
            httpVersion: nil,
            headerFields: nil
        )!
        fixture.transport.register(path: "/safe-delete") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload.count == 1)
            #expect(payload["recovery_capability"] as? String == capability)
            return (
                mockResponse,
                Data(
                    """
                    {"success":true,"status":"pending","manual_provider_revocation_required":false,"recovery_capability_expires_at":"\(expiry)"}
                    """.utf8
                )
            )
        }

        let receipt = try await fixture.client.safeDeleteAccount(
            recoveryCapability: capability
        )

        #expect(receipt.status == .pending)
        #expect(receipt.recoveryCapabilityExpiresAt == expiry)
    }

    @Test func testSafeDeleteAccountRejectsMissingProviderRevocationDisposition() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 202,
            httpVersion: nil,
            headerFields: nil
        )!
        fixture.transport.register(path: "/safe-delete") { _ in
            (
                mockResponse,
                Data(#"{"success":true,"status":"pending"}"#.utf8)
            )
        }

        await #expect(throws: MerianError.invalidResponse) {
            _ = try await fixture.client.safeDeleteAccount()
        }
    }

    @Test(arguments: [false, true])
    func prepareRejectsMalformedOrIdenticalProofsBeforeIO(identical: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let owner = AuthTransitionToken(id: UUID(), kind: .accountDeletion)
        await confirmation("No invalid preparation request", expectedCount: 0) { sent in
            fixture.transport.register(path: "/safe-delete") { _ in sent(); throw URLError(.badServerResponse) }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.prepareAccountDeletionRecoveryV2(
                    recoveryCapability: AccountDeletionTestSupport.recovery,
                    acknowledgementCapability: identical ? AccountDeletionTestSupport.recovery : "invalid",
                    ownedBy: owner
                )
            }
        }
    }

    @Test func malformedCommitAndLegacyProofsFailBeforeIO() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No malformed-proof intake", expectedCount: 0) { sent in
            fixture.transport.register(path: "/safe-delete") { _ in sent(); throw URLError(.badServerResponse) }
            await #expect(throws: MerianError.invalidResponse) { try await fixture.client.safeDeleteAccount(recoveryCapability: "invalid") }
            await #expect(throws: MerianError.invalidResponse) {
                try await fixture.client.commitPreparedAccountDeletionV2(
                    recoveryCapability: "invalid", ownedBy: AuthTransitionToken(id: UUID(), kind: .accountDeletion)
                )
            }
        }
    }

    @Test(arguments: [false, true])
    func versionTwoRequestsCannotBypassAnUnownedTransition(preparing: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let owner = AuthTransitionToken(id: UUID(), kind: .accountDeletion)
        // An injected session deliberately does not admit a transition owner.
        // Accepted-owner workflow tests remain with SupabaseManagerTests.
        await confirmation("No request from a stale transition", expectedCount: 0) { sent in
            fixture.transport.register(path: "/safe-delete") { _ in sent(); throw URLError(.badServerResponse) }
            await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
                if preparing {
                    _ = try await fixture.client.prepareAccountDeletionRecoveryV2(
                        recoveryCapability: AccountDeletionTestSupport.recovery,
                        acknowledgementCapability: AccountDeletionTestSupport.acknowledgement,
                        ownedBy: owner
                    )
                } else {
                    _ = try await fixture.client.commitPreparedAccountDeletionV2(
                        recoveryCapability: AccountDeletionTestSupport.recovery,
                        ownedBy: owner
                    )
                }
            }
        }
    }

    @Test func classifiedAuthRefreshKeepsTheExactLegacyBody() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let snapshots = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        try await confirmation("One classified Auth refresh") { refreshed in
            fixture.client.overridingAuthSessionRefresh = { refreshed(); return true }
            fixture.transport.register(path: "/safe-delete") { request in
                let json = "{\"recovery_capability\":\"\(AccountDeletionTestSupport.recovery)\"}"
                let snapshot = try NetworkEndpointTestSupport.expectPOST(request, function: "safe-delete", json: json)
                let attempt = snapshots.withLock { values in values.append(snapshot); return values.count }
                if attempt == 1 {
                    return try NetworkEndpointTestSupport.response(
                        to: request, status: 401, json: #"{"code":"invalid_session_token","error":"Synthetic invalid session"}"#
                    )
                }
                let (response, _) = try NetworkEndpointTestSupport.response(to: request, status: 202, json: "{}")
                return (response, try AccountDeletionTestSupport.receiptData())
            }
            let receipt = try await fixture.client.safeDeleteAccount(recoveryCapability: AccountDeletionTestSupport.recovery)
            #expect(receipt.status == .pending)
        }
        #expect(snapshots.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: [false, true])
    func legacyIntakeDoesNotReplayAnAmbiguousFailure(serverFailure: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("One unkeyed intake") { sent in
            fixture.transport.register(path: "/safe-delete") { request in
                sent()
                #expect(MockURLProtocol.bodyData(for: request) == nil)
                if serverFailure {
                    return try NetworkEndpointTestSupport.response(to: request, status: 503, json: "{}")
                }
                throw URLError(.networkConnectionLost)
            }
            do {
                _ = try await fixture.client.safeDeleteAccount()
                Issue.record("Ambiguous intake failure must propagate")
            } catch MerianError.httpError(let status, _) {
                #expect(serverFailure && status == 503)
            } catch let error as URLError {
                #expect(!serverFailure && error.code == .networkConnectionLost)
            }
        }
    }

    @Test func cancelledIntakeDoesNotDispatch() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No cancelled intake", expectedCount: 0) { sent in
            fixture.transport.register(path: "/safe-delete") { _ in sent(); throw URLError(.badServerResponse) }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await fixture.client.safeDeleteAccount()
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }
}
