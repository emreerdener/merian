import Foundation
@testable import Merian
import Testing

@Suite("Purchase Identity Session Live Service")
@MainActor
struct PurchaseIdentitySessionLiveServiceTests {
    @Test func legacySnapshotPreservesProfilePrecedenceAndAccountKind()
        async {
        let harness = SessionLiveServiceHarness()
        harness.publicProfile = LegacyPurchaseIdentityProfile(
            email: "public@example.test",
            publicUsername: "river_wren",
            publicAuthorName: "River W.",
            publicIdentitySource: "derived_name",
            publicAvatarURL: "https://example.test/public.jpg"
        )
        let profile = harness.profile(
            isAnonymous: false,
            email: "  auth@example.test ",
            fullName: " Auth Name ",
            pictureURL: "https://example.test/auth.jpg"
        )
        let snapshot = harness.service.snapshot(
            for: profile,
            isExpired: true
        )

        await snapshot.linkLegacyProviderIdentity()

        #expect(snapshot.userID == profile.userID)
        #expect(!snapshot.isAnonymous)
        #expect(snapshot.isExpired)
        #expect(harness.fetchedUserIDs == [profile.userID])
        #expect(harness.linkRequests == [
            PurchaseIdentityLegacyLinkRequest(
                userID: profile.userID,
                email: "auth@example.test",
                displayName: "Auth Name",
                avatarURL: "https://example.test/auth.jpg",
                publicUsername: "river_wren",
                publicAuthorName: "River W.",
                publicIdentitySource: "derived_name",
                accountKind: "authenticated"
            )
        ])
    }

    @Test func failedProfileLookupStillLinksAuthMetadata() async {
        let harness = SessionLiveServiceHarness()
        harness.profileError = SessionLiveServiceTestError.failed
        let profile = harness.profile(
            isAnonymous: true,
            email: "ghost@example.test",
            name: "Ghost Name",
            avatarURL: "https://example.test/ghost.jpg"
        )

        await harness.service.linkLegacyProviderIdentity(for: profile)

        #expect(harness.profileFailureCount == 1)
        #expect(harness.linkRequests == [
            PurchaseIdentityLegacyLinkRequest(
                userID: profile.userID,
                email: "ghost@example.test",
                displayName: "Ghost Name",
                avatarURL: "https://example.test/ghost.jpg",
                publicUsername: nil,
                publicAuthorName: nil,
                publicIdentitySource: nil,
                accountKind: "anonymous"
            )
        ])
    }

    @Test func blankAuthMetadataFallsBackToPublicProfile() async {
        let harness = SessionLiveServiceHarness()
        harness.publicProfile = LegacyPurchaseIdentityProfile(
            email: "public@example.test",
            publicUsername: "river_wren",
            publicAuthorName: "River W.",
            publicIdentitySource: "derived_name",
            publicAvatarURL: "https://example.test/public.jpg"
        )
        let profile = harness.profile(
            isAnonymous: false,
            email: "  \n",
            fullName: "",
            name: "  ",
            avatarURL: "\t"
        )

        await harness.service.linkLegacyProviderIdentity(for: profile)

        #expect(harness.linkRequests == [
            PurchaseIdentityLegacyLinkRequest(
                userID: profile.userID,
                email: "public@example.test",
                displayName: "River W.",
                avatarURL: "https://example.test/public.jpg",
                publicUsername: "river_wren",
                publicAuthorName: "River W.",
                publicIdentitySource: "derived_name",
                accountKind: "authenticated"
            )
        ])
    }

    @Test func dependenciesForwardProviderEntitlementAndDiagnostics()
        async throws {
        let harness = SessionLiveServiceHarness()
        let dependencies = harness.service.dependencies(
            state: harness.stateBoundary,
            handoff: harness.handoffBoundary
        )

        dependencies.provider.beginResolution()
        let binding = try await dependencies.provider.resolve("fingerprint", true)
        await dependencies.provider.applyStableBinding(
            binding,
            harness.userID,
            "authenticated"
        )
        #expect(dependencies.provider.currentState() == harness.providerState)
        #expect(dependencies.entitlement.isReady(harness.userID))
        #expect(await dependencies.entitlement.beginSession(harness.userID))
        dependencies.reportHandoffStateFailure(
            SessionLiveServiceTestError.failed
        )
        dependencies.reportDeferredForHandoff()
        dependencies.reportResolutionFailure(
            SessionLiveServiceTestError.failed
        )

        #expect(harness.events == [
            "begin-resolution",
            "resolve:fingerprint:true",
            "apply-stable:\(harness.userID.uuidString):authenticated",
            "begin-entitlement:\(harness.userID.uuidString)",
            "handoff-failure",
            "handoff-deferred",
            "resolution-failure"
        ])
    }

    @Test func legacyReadinessForwardsTheExactAccount() {
        let harness = SessionLiveServiceHarness()
        harness.readyLegacyUserID = harness.userID

        #expect(
            harness.service.legacyProviderIsReady(for: harness.userID)
        )
        #expect(
            !harness.service.legacyProviderIsReady(for: UUID())
        )
        #expect(harness.readinessChecks.count == 2)
    }

    @Test func releasedServiceRejectsDeferredFacadeOwnedEffects() async {
        let harness = SessionLiveServiceHarness()
        let profile = harness.profile(isAnonymous: false)
        var service: PurchaseIdentitySessionLiveService? = harness.makeService()
        let snapshot = service?.snapshot(for: profile)
        let dependencies = service?.dependencies(
            state: harness.stateBoundary,
            handoff: harness.handoffBoundary
        )

        service = nil

        await snapshot?.linkLegacyProviderIdentity()
        let entitlementStarted = await dependencies?.entitlement
            .beginSession(harness.userID) ?? true
        #expect(!entitlementStarted)
        #expect(harness.fetchedUserIDs.isEmpty)
        #expect(harness.linkRequests.isEmpty)
        #expect(harness.events.isEmpty)
    }
}

@MainActor
private final class SessionLiveServiceHarness {
    let userID = UUID()
    var publicProfile: LegacyPurchaseIdentityProfile?
    var profileError: Error?
    var fetchedUserIDs: [UUID] = []
    var linkRequests: [PurchaseIdentityLegacyLinkRequest] = []
    var profileFailureCount = 0
    var readyLegacyUserID: UUID?
    var readinessChecks: [UUID] = []
    var events: [String] = []
    var providerState = PurchaseIdentityProviderState(
        isIdentityReady: true,
        linkedAuthUserID: nil,
        linkedAccountKind: "authenticated"
    )

    lazy var service = makeService()

    func makeService() -> PurchaseIdentitySessionLiveService {
        PurchaseIdentitySessionLiveService(
            operations: PurchaseIdentitySessionLiveOperations(
                fetchLegacyProfile: { [unowned self] userID in
                    fetchedUserIDs.append(userID)
                    if let profileError { throw profileError }
                    return publicProfile
                },
                linkLegacyProviderIdentity: { [unowned self] request in
                    linkRequests.append(request)
                },
                beginResolution: { [unowned self] in
                    events.append("begin-resolution")
                },
                resolve: { [unowned self] fingerprint, allowsCreation in
                    events.append(
                        "resolve:\(fingerprint ?? "nil"):\(allowsCreation)"
                    )
                    return .legacyFallback
                },
                applyStableBinding: { [unowned self] _, userID, accountKind in
                    events.append(
                        "apply-stable:\(userID.uuidString):\(accountKind)"
                    )
                },
                currentProviderState: { [unowned self] in providerState },
                legacyProviderIsReady: { [unowned self] userID in
                    readinessChecks.append(userID)
                    return readyLegacyUserID == userID
                },
                entitlementIsReady: { [unowned self] userID in
                    userID == self.userID
                },
                beginEntitlementSession: { [unowned self] userID in
                    events.append("begin-entitlement:\(userID.uuidString)")
                    return userID == self.userID
                },
                reportLegacyProfileFailure: { [unowned self] _ in
                    profileFailureCount += 1
                },
                reportHandoffStateFailure: { [unowned self] _ in
                    events.append("handoff-failure")
                },
                reportDeferredForHandoff: { [unowned self] in
                    events.append("handoff-deferred")
                },
                reportResolutionFailure: { [unowned self] _ in
                    events.append("resolution-failure")
                }
            )
        )
    }

    var stateBoundary: PurchaseIdentitySessionStateBoundary {
        PurchaseIdentitySessionStateBoundary(
            isTestExecution: { false },
            accountDeletionCleanupPending: { false },
            isSigningOut: { false },
            isAuthenticated: { true },
            isUserSignOutTransitionInProgress: { false },
            currentPublishedSession: { nil },
            isCurrentPublishedSession: { _ in true },
            beginAccountWork: { _ in nil },
            loadSDKSession: {
                throw SessionLiveServiceTestError.failed
            }
        )
    }

    var handoffBoundary: PurchaseIdentitySessionHandoffBoundary {
        PurchaseIdentitySessionHandoffBoundary(
            loadPending: { false },
            setPending: { _ in },
            completePending: { _ in false },
            abandonRestoredSource: { _ in }
        )
    }

    func profile(
        isAnonymous: Bool,
        email: String? = nil,
        fullName: String? = nil,
        name: String? = nil,
        avatarURL: String? = nil,
        pictureURL: String? = nil
    ) -> PurchaseIdentityLegacySessionProfile {
        PurchaseIdentityLegacySessionProfile(
            userID: userID,
            isAnonymous: isAnonymous,
            email: email,
            fullName: fullName,
            name: name,
            avatarURL: avatarURL,
            pictureURL: pictureURL
        )
    }
}

private enum SessionLiveServiceTestError: Error {
    case failed
}
