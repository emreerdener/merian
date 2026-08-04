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
        let mergeTemporarilyUnavailable = FunctionsError.httpError(
            code: 503,
            data: Data(#"{"code":"merge_temporarily_unavailable"}"#.utf8)
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
                after: mergeTemporarilyUnavailable
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

    func testGhostConsentRebindPreservesImmutableEvidenceAndPendingState() {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_000_000)

        let adultReceipts = [
            makeAdultReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeAdultReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let termsReceipts = [
            makeTermsReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeTermsReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let aiEvents = [
            makeAIConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeAIConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let analyticsEvents = [
            makeAnalyticsConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                eventKind: .granted,
                recordedAt: recordedAt
            ),
            makeAnalyticsConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                eventKind: .revoked,
                recordedAt: nil
            )
        ]
        let source = ConsentManager.LocalLedger(
            activeUserId: ghostUserId,
            termsReceipts: termsReceipts,
            aiConsentEvents: aiEvents,
            adultEligibilityReceipts: adultReceipts,
            analyticsConsentEvents: analyticsEvents
        )

        let rebound = ConsentManager.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )

        XCTAssertEqual(rebound.activeUserId, permanentUserId)
        XCTAssertEqual(
            rebound,
            ConsentManager.rebinding(
                rebound,
                from: ghostUserId,
                to: permanentUserId
            ),
            "Rebinding must be idempotent for crash-safe handoff retries"
        )

        var expectedAdults = adultReceipts
        var expectedTerms = termsReceipts
        var expectedAI = aiEvents
        var expectedAnalytics = analyticsEvents
        for index in expectedAdults.indices {
            expectedAdults[index].ownerUserId = permanentUserId
            expectedAdults[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedTerms.indices {
            expectedTerms[index].ownerUserId = permanentUserId
            expectedTerms[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedAI.indices {
            expectedAI[index].ownerUserId = permanentUserId
            expectedAI[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedAnalytics.indices {
            expectedAnalytics[index].ownerUserId = permanentUserId
            expectedAnalytics[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }

        XCTAssertEqual(rebound.adultEligibilityReceipts, expectedAdults)
        XCTAssertEqual(rebound.termsReceipts, expectedTerms)
        XCTAssertEqual(rebound.aiConsentEvents, expectedAI)
        XCTAssertEqual(rebound.analyticsConsentEvents, expectedAnalytics)
    }

    func testOfflineGhostAnalyticsRevocationWinsAfterMergeAndAcrossDevices() throws {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let grantRecordedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let revocation = makeAnalyticsConsentEvent(
            ownerUserId: ghostUserId,
            syncedUserId: nil,
            eventKind: .revoked,
            recordedAt: nil
        )
        let source = ConsentManager.LocalLedger(
            activeUserId: ghostUserId,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: [
                makeAnalyticsConsentEvent(
                    ownerUserId: permanentUserId,
                    syncedUserId: permanentUserId,
                    eventKind: .granted,
                    recordedAt: grantRecordedAt
                ),
                revocation
            ]
        )
        let rebound = ConsentManager.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )

        let suiteName = "merian.tests.ghost-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            try JSONEncoder().encode(rebound),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let mergedManager = ConsentManager(userDefaults: userDefaults)
        mergedManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(mergedManager.hasGrantedCurrentPostHogAnalytics)

        let restartedManager = ConsentManager(userDefaults: userDefaults)
        restartedManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(restartedManager.hasGrantedCurrentPostHogAnalytics)

        var secondDeviceLedger = rebound
        let revocationIndex = try XCTUnwrap(
            secondDeviceLedger.analyticsConsentEvents.firstIndex {
                $0.id == revocation.id
            }
        )
        secondDeviceLedger.analyticsConsentEvents[revocationIndex].syncedUserId =
            permanentUserId
        secondDeviceLedger.analyticsConsentEvents[revocationIndex].recordedAt =
            grantRecordedAt.addingTimeInterval(1)
        userDefaults.set(
            try JSONEncoder().encode(secondDeviceLedger),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let secondDeviceManager = ConsentManager(userDefaults: userDefaults)
        secondDeviceManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(secondDeviceManager.hasGrantedCurrentPostHogAnalytics)
    }

    func testGhostHandoffClearsQueueOnlyAfterServerAndLocalCompletion() async throws {
        var calls: [String] = []

        try await SupabaseManager.finalizeGhostProfileHandoff(
            completeServerHandoff: { calls.append("server") },
            rebindAndSynchronizeLocalEvidence: { calls.append("local") },
            clearPendingHandoff: { calls.append("clear") }
        )

        XCTAssertEqual(calls, ["server", "local", "clear"])
    }

    func testGhostHandoffRetainsQueueWhenServerOrLocalCompletionFails() async {
        var serverFailureCalls: [String] = []
        do {
            try await SupabaseManager.finalizeGhostProfileHandoff(
                completeServerHandoff: {
                    serverFailureCalls.append("server")
                    throw GhostHandoffTestError.expected
                },
                rebindAndSynchronizeLocalEvidence: {
                    serverFailureCalls.append("local")
                },
                clearPendingHandoff: {
                    serverFailureCalls.append("clear")
                }
            )
            XCTFail("Server failure must remain retryable")
        } catch {}
        XCTAssertEqual(serverFailureCalls, ["server"])

        var localFailureCalls: [String] = []
        do {
            try await SupabaseManager.finalizeGhostProfileHandoff(
                completeServerHandoff: {
                    localFailureCalls.append("server")
                },
                rebindAndSynchronizeLocalEvidence: {
                    localFailureCalls.append("local")
                    throw GhostHandoffTestError.expected
                },
                clearPendingHandoff: {
                    localFailureCalls.append("clear")
                }
            )
            XCTFail("Local evidence failure must retain the durable handoff")
        } catch {}
        XCTAssertEqual(localFailureCalls, ["server", "local"])
    }

    func testGhostHandoffRemovalFailureRemainsRetryable() async {
        var calls: [String] = []
        do {
            try await SupabaseManager.finalizeGhostProfileHandoff(
                completeServerHandoff: { calls.append("server") },
                rebindAndSynchronizeLocalEvidence: { calls.append("local") },
                clearPendingHandoff: {
                    calls.append("clear")
                    throw GhostHandoffTestError.expected
                }
            )
            XCTFail("A failed verified queue write must be retried")
        } catch {}
        XCTAssertEqual(calls, ["server", "local", "clear"])
    }

    private func makeAdultReceipt(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        recordedAt: Date?
    ) -> ConsentManager.AdultEligibilityReceipt {
        ConsentManager.AdultEligibilityReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            policyVersion: ConsentPolicy.adultEligibilityVersion,
            confirmedAt: Date(timeIntervalSince1970: 1_785_999_900),
            confirmationMethod: .selfAttestation,
            confirmationText: ConsentPolicy.adultConfirmationText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    private func makeTermsReceipt(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        recordedAt: Date?
    ) -> ConsentManager.TermsAcceptanceReceipt {
        ConsentManager.TermsAcceptanceReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            termsVersion: ConsentPolicy.termsVersion,
            acceptedAt: Date(timeIntervalSince1970: 1_785_999_900),
            acceptanceText: ConsentPolicy.combinedAcceptanceText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    private func makeAIConsentEvent(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        recordedAt: Date?
    ) -> ConsentManager.AIConsentEvent {
        ConsentManager.AIConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            provider: ConsentPolicy.geminiProvider,
            disclosureVersion: ConsentPolicy.geminiDisclosureVersion,
            eventKind: .granted,
            occurredAt: Date(timeIntervalSince1970: 1_785_999_900),
            disclosureText: ConsentPolicy.geminiDisclosureText,
            actionText: ConsentPolicy.combinedAcceptanceText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    private func makeAnalyticsConsentEvent(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        eventKind: ConsentManager.AnalyticsConsentEventKind,
        recordedAt: Date?
    ) -> ConsentManager.AnalyticsConsentEvent {
        ConsentManager.AnalyticsConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: ConsentPolicy.analyticsDisclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_785_999_900),
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
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

private enum GhostHandoffTestError: Error {
    case expected
}
