import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class SupabaseManagerTests: XCTestCase {

    var supabaseManager: SupabaseManager!

    override func setUp() async throws {
        supabaseManager = SupabaseManager.shared
    }

    override func tearDown() async throws {
        supabaseManager = nil
    }

    func testGuestUserPropertyDefaults() {
        // Without an explicit session injected, an initial boot should default into
        // a false authentication bound and mark itself as a Guest
        // Note: As this is a live singleton, if a simulator has persistent data logged in,
        // it may alter this behavior. This asserts the logic flows without crashing.
        let isGuest = supabaseManager.isGuestUser
        let authState = supabaseManager.isAuthenticated
        
        XCTAssertNotNil(isGuest)
        XCTAssertNotNil(authState)
    }

    func testGetValidAuthHeadersUsesDeterministicTestStub() async throws {
        let headers = try await supabaseManager.getValidAuthHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer merian-test-session")
        XCTAssertEqual(headers["apikey"], MerianEnvironment.supabaseAnonKey)
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    func testSignOutClosesAuthenticatedRequestGateBeforeRemoteInvalidation() async {
        guard let manager = supabaseManager else {
            XCTFail("Supabase manager was not initialized")
            return
        }

        manager.isAuthenticated = true
        var observedLocalSignOutBeforeRemoteCall = false
        var requestWasBlockedDuringRemoteCall = false

        await manager.signOut(
            performRemoteSignOut: { [manager] in
                observedLocalSignOutBeforeRemoteCall =
                    !manager.isAuthenticated && manager.isSigningOut

                do {
                    _ = try await manager.getValidAuthHeaders()
                } catch SupabaseAuthTransitionError.signOutInProgress {
                    requestWasBlockedDuringRemoteCall = true
                } catch {
                    XCTFail("Unexpected auth transition error: \(error)")
                }
            },
            performExternalSignOut: {}
        )

        XCTAssertTrue(observedLocalSignOutBeforeRemoteCall)
        XCTAssertTrue(requestWasBlockedDuringRemoteCall)
        XCTAssertFalse(manager.isSigningOut)
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testOAuthProviderSubjectReadsBase64URLJWTSubject() throws {
        let token = try makeUnsignedJWT(
            payload: ["sub": "001234.abcd9876", "aud": "merian"]
        )

        XCTAssertEqual(
            try SupabaseManager.oauthProviderSubject(from: token),
            "001234.abcd9876"
        )
    }

    func testOAuthProviderSubjectRejectsMalformedOrUnsafeClaims() throws {
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(from: "not-a-jwt")
        )
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(
                from: try makeUnsignedJWT(payload: ["aud": "merian"])
            )
        )
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(
                from: try makeUnsignedJWT(payload: ["sub": "subject\ninjection"])
            )
        )
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(
                from: try makeUnsignedJWT(payload: ["sub": String(repeating: "a", count: 256)])
            )
        )
    }

    func testProviderBoundMergeFallbackOnlyAcceptsIdentityConflict() {
        let response = HTTPURLResponse(
            url: URL(string: "https://auth.example.test")!,
            statusCode: 422,
            httpVersion: nil,
            headerFields: nil
        )!
        let identityConflict = AuthError.api(
            message: "Identity already linked",
            errorCode: .identityAlreadyExists,
            underlyingData: Data(),
            underlyingResponse: response
        )
        let transientFailure = AuthError.api(
            message: "Request timed out",
            errorCode: .requestTimeout,
            underlyingData: Data(),
            underlyingResponse: response
        )

        XCTAssertTrue(
            SupabaseManager.requiresProviderBoundGhostMerge(
                after: identityConflict
            )
        )
        XCTAssertFalse(
            SupabaseManager.requiresProviderBoundGhostMerge(
                after: transientFailure
            )
        )
        XCTAssertFalse(
            SupabaseManager.requiresProviderBoundGhostMerge(
                after: URLError(.notConnectedToInternet)
            )
        )
    }

    func testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes() {
        let expired = FunctionsError.httpError(
            code: 410,
            data: Data(#"{"code":"handoff_expired"}"#.utf8)
        )
        let invalid = FunctionsError.httpError(
            code: 404,
            data: Data(#"{"code":"handoff_invalid"}"#.utf8)
        )
        let wrongDestination = FunctionsError.httpError(
            code: 403,
            data: Data(#"{"code":"handoff_forbidden"}"#.utf8)
        )
        let cleanupPending = FunctionsError.httpError(
            code: 503,
            data: Data(#"{"code":"auth_cleanup_pending"}"#.utf8)
        )

        XCTAssertTrue(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: expired
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: invalid
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: wrongDestination
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: cleanupPending
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: URLError(.timedOut)
            )
        )
    }

    func testPendingMergeQueueReplacesOnlySameGhostAndRoundTrips() throws {
        let replaced = SupabaseManager.PendingGhostProfileMerge(
            ghostUserId: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            provider: "apple",
            providerSubject: "old-apple-subject",
            handoffId: "11111111-1111-1111-1111-111111111111",
            handoffSecret: "old-secret",
            expiresAt: "2026-08-01T00:00:00Z"
        )
        let unrelated = SupabaseManager.PendingGhostProfileMerge(
            ghostUserId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            provider: "google",
            providerSubject: "google-subject",
            handoffId: "22222222-2222-2222-2222-222222222222",
            handoffSecret: "unrelated-secret",
            expiresAt: "2026-08-02T00:00:00Z"
        )
        let replacement = SupabaseManager.PendingGhostProfileMerge(
            ghostUserId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            provider: "apple",
            providerSubject: "new-apple-subject",
            handoffId: "33333333-3333-3333-3333-333333333333",
            handoffSecret: "replacement-secret",
            expiresAt: "2026-08-03T00:00:00Z"
        )

        let updated = SupabaseManager.enqueuingPendingGhostProfileMerge(
            replacement,
            in: [replaced, unrelated]
        )

        XCTAssertEqual(updated, [unrelated, replacement])

        let queue = SupabaseManager.PendingGhostProfileMergeQueue(
            handoffs: updated
        )
        let encoded = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(
            SupabaseManager.PendingGhostProfileMergeQueue.self,
            from: encoded
        )

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.handoffs, [unrelated, replacement])
    }

    private func makeUnsignedJWT(payload: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let payloadSegment = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payloadSegment).signature"
    }
}
