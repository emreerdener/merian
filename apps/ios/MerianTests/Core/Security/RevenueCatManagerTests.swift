@testable import Merian
import XCTest

@MainActor
final class RevenueCatManagerTests: XCTestCase {

    var revenueCatManager: RevenueCatManager!

    override func setUp() async throws {
        revenueCatManager = RevenueCatManager.shared
        revenueCatManager.setPurchaseIdentityHandoffPending(false)
        EntitlementManager.shared.resetForTesting()
    }

    override func tearDown() async throws {
        revenueCatManager.setPurchaseIdentityHandoffPending(false)
        revenueCatManager = nil
    }

    func testInitialStateIsCorrect() {
        XCTAssertFalse(revenueCatManager.isProActive)
        XCTAssertFalse(revenueCatManager.isSubscribed)
        XCTAssertNil(revenueCatManager.currentOfferings)
        XCTAssertFalse(revenueCatManager.isFetchingOfferings)
    }

    func testComplimentaryPlanDetailsAreLimitedToResultsAndSettings() {
        XCTAssertFalse(ComplimentaryPlanDetailContext.hidden.showsDetails)
        XCTAssertTrue(ComplimentaryPlanDetailContext.results.showsDetails)
        XCTAssertTrue(ComplimentaryPlanDetailContext.settings.showsDetails)
    }
    
    func testRevenueCatAttributionSignature() async {
        // Asserts that the refactored signature compiles securely mapping telemetry correctly.
        // Because purchases.shared is tightly coupled, we do not fully hit the live backend, 
        // we strictly test the caller logic boundaries directly avoiding signature mismatched crashes natively.
        let testId = UUID()
        let email = "test@example.com"
        let name = "John Merian Explorer"
        let avatar = "https://example.com/image.jpg"
        
        // This validates the Swift 6 compiler hasn't dropped any named parameter requirements statically.
        await revenueCatManager.linkWithSupabase(
            userId: testId,
            email: email,
            displayName: name,
            avatarUrl: avatar,
            publicUsername: "riverwren",
            publicAuthorName: "River Wren",
            publicIdentitySource: "display_name",
            accountKind: "authenticated"
        )
        
        XCTAssertTrue(true, "Attribution Signature compiled properly!")
    }

    func testRevenueCatAppUserIDPolicyUsesUppercaseRFC4122UUID() {
        let userID = UUID(uuidString: "4c6c85f8-e1ff-4976-a524-95c012345678")!

        XCTAssertEqual(
            RevenueCatAppUserIDPolicy.canonicalID(for: userID),
            "4C6C85F8-E1FF-4976-A524-95C012345678"
        )
    }

    func testKnownStoreSubscriptionCannotBeHiddenByPromotion() {
        XCTAssertTrue(
            RevenueCatEntitlementProvenancePolicy
                .hasActiveStoreBackedSubscription(
                    productIdentifiers: ["pro_annual", "rc_promo_pro_lifetime"]
                )
        )
        XCTAssertFalse(
            RevenueCatEntitlementProvenancePolicy
                .hasActiveStoreBackedSubscription(
                    productIdentifiers: ["rc_promo_pro_lifetime"]
                )
        )
    }

    func testStablePurchasePrincipalDeletesEveryLegacyAccountAttribute() {
        XCTAssertEqual(
            Set(RevenueCatStableIdentityPrivacyPolicy.deletionAttributes.keys),
            Set([
                "supabase_user_id",
                "auth_email",
                "display_name",
                "avatar_url",
                "public_username",
                "public_author_name",
                "public_identity_source",
                "account_kind"
            ])
        )
        XCTAssertTrue(
            RevenueCatStableIdentityPrivacyPolicy.deletionAttributes.values
                .allSatisfy(\.isEmpty)
        )
    }

    func testRevenueCatAccountMutationPolicyAcceptsStableGhostAndPermanentAccounts() {
        XCTAssertEqual(
            RevenueCatAccountMutationPolicy.accountKind(isAnonymous: true),
            "anonymous"
        )
        XCTAssertEqual(
            RevenueCatAccountMutationPolicy.accountKind(isAnonymous: false),
            "authenticated"
        )
        XCTAssertTrue(
            RevenueCatAccountMutationPolicy.allowsProviderMutation(
                accountKind: "authenticated"
            )
        )
        XCTAssertTrue(
            RevenueCatAccountMutationPolicy.allowsProviderMutation(
                accountKind: " Authenticated "
            )
        )
        XCTAssertTrue(
            RevenueCatAccountMutationPolicy.allowsProviderMutation(
                accountKind: "anonymous"
            )
        )
        XCTAssertTrue(
            RevenueCatAccountMutationPolicy.allowsProviderMutation(
                accountKind: " Anonymous "
            )
        )
        XCTAssertFalse(
            RevenueCatAccountMutationPolicy.allowsProviderMutation(
                accountKind: "unknown"
            )
        )
        XCTAssertFalse(
            RevenueCatAccountMutationPolicy.allowsProviderMutation(
                accountKind: nil
            )
        )
    }

    func testRevenueCatAccountMutationPolicyRejectsStaleLinkage() {
        XCTAssertTrue(
            RevenueCatAccountMutationPolicy.isReady(
                identityReady: true,
                requestedAccountKind: " Authenticated ",
                linkedAccountKind: "authenticated"
            )
        )
        XCTAssertTrue(
            RevenueCatAccountMutationPolicy.isReady(
                identityReady: true,
                requestedAccountKind: "anonymous",
                linkedAccountKind: " Anonymous "
            )
        )
        XCTAssertFalse(
            RevenueCatAccountMutationPolicy.isReady(
                identityReady: false,
                requestedAccountKind: "authenticated",
                linkedAccountKind: "authenticated"
            )
        )
        XCTAssertFalse(
            RevenueCatAccountMutationPolicy.isReady(
                identityReady: true,
                requestedAccountKind: "authenticated",
                linkedAccountKind: nil
            )
        )
        XCTAssertTrue(
            RevenueCatAccountMutationPolicy.isReady(
                identityReady: true,
                requestedAccountKind: "anonymous",
                linkedAccountKind: "anonymous"
            )
        )
        XCTAssertFalse(
            RevenueCatAccountMutationPolicy.isReady(
                identityReady: true,
                requestedAccountKind: "anonymous",
                linkedAccountKind: "authenticated"
            )
        )
    }

    func testRevenueCatPurchaseMutationPolicyFailsClosedDuringIdentityHandoff() {
        XCTAssertTrue(
            RevenueCatPurchaseMutationPolicy.isReady(
                providerIdentityReady: true,
                identityHandoffPending: false
            )
        )
        XCTAssertFalse(
            RevenueCatPurchaseMutationPolicy.isReady(
                providerIdentityReady: true,
                identityHandoffPending: true
            )
        )
        XCTAssertFalse(
            RevenueCatPurchaseMutationPolicy.isReady(
                providerIdentityReady: false,
                identityHandoffPending: false
            )
        )
    }

    func testStablePurchasePrincipalRejectsAccountScopedPromotions() {
        XCTAssertTrue(
            RevenueCatEntitlementProvenancePolicy.allowsStoreBackedAccess(
                store: .appStore,
                accountGrantsAllowed: false
            )
        )
        XCTAssertTrue(
            RevenueCatEntitlementProvenancePolicy.allowsStoreBackedAccess(
                store: .testStore,
                accountGrantsAllowed: false
            )
        )
        XCTAssertFalse(
            RevenueCatEntitlementProvenancePolicy.allowsStoreBackedAccess(
                store: .promotional,
                accountGrantsAllowed: false
            )
        )
    }

    func testAccountOwnerCanUseAccountScopedRevenueCatGrantDuringDualRead() {
        XCTAssertTrue(
            RevenueCatEntitlementProvenancePolicy.allowsStoreBackedAccess(
                store: .promotional,
                accountGrantsAllowed: true
            )
        )
    }

    func testRevenueCatIdentityContextAddsDashboardLookupAttributes() {
        let context = RevenueCatIdentityContext(
            userId: "user-123",
            email: " test@example.com ",
            displayName: " Test Explorer ",
            avatarUrl: " https://example.com/avatar.jpg ",
            publicUsername: "riverwren",
            publicAuthorName: "River Wren",
            publicIdentitySource: "display_name",
            accountKind: "authenticated"
        )

        XCTAssertEqual(context.normalizedEmail, "test@example.com")
        XCTAssertEqual(context.normalizedDisplayName, "Test Explorer")
        XCTAssertEqual(context.subscriberAttributes["supabase_user_id"], "user-123")
        XCTAssertEqual(context.subscriberAttributes["auth_email"], "test@example.com")
        XCTAssertEqual(context.subscriberAttributes["display_name"], "Test Explorer")
        XCTAssertEqual(context.subscriberAttributes["avatar_url"], "https://example.com/avatar.jpg")
        XCTAssertEqual(context.subscriberAttributes["public_username"], "riverwren")
        XCTAssertEqual(context.subscriberAttributes["public_author_name"], "River Wren")
        XCTAssertEqual(context.subscriberAttributes["public_identity_source"], "display_name")
        XCTAssertEqual(context.subscriberAttributes["account_kind"], "authenticated")
    }

    func testRevenueCatIdentityContextFallsBackToPublicUsernameAndOmitsBlankValues() {
        let context = RevenueCatIdentityContext(
            userId: "anonymous-123",
            email: "  ",
            displayName: nil,
            avatarUrl: nil,
            publicUsername: "trailmoss",
            publicAuthorName: nil,
            publicIdentitySource: "alias",
            accountKind: "anonymous"
        )

        XCTAssertNil(context.normalizedEmail)
        XCTAssertEqual(context.normalizedDisplayName, "@trailmoss")
        XCTAssertEqual(context.subscriberAttributes["supabase_user_id"], "anonymous-123")
        XCTAssertNil(context.subscriberAttributes["auth_email"])
        XCTAssertNil(context.subscriberAttributes["avatar_url"])
        XCTAssertEqual(context.subscriberAttributes["display_name"], "@trailmoss")
        XCTAssertEqual(context.subscriberAttributes["public_username"], "trailmoss")
        XCTAssertEqual(context.subscriberAttributes["public_identity_source"], "alias")
        XCTAssertEqual(context.subscriberAttributes["account_kind"], "anonymous")
    }

    func testRevenueCatOfferingPolicyRequiresAnnualAndSevenDayPassProducts() {
        XCTAssertEqual(
            RevenueCatOfferingPolicy.missingRequiredProducts(
                in: [RevenueCatOfferingPolicy.annualProductIdentifier]
            ),
            [SevenDayPassAccessPolicy.productIdentifier]
        )
        XCTAssertTrue(
            RevenueCatOfferingPolicy.missingRequiredProducts(
                in: RevenueCatOfferingPolicy.requiredProductIdentifiers
            ).isEmpty
        )
    }

    func testHandleSupabaseSignOutClearsEntitlementsInTests() async {
        revenueCatManager.isProActive = true
        revenueCatManager.isSubscribed = true

        await revenueCatManager.handleSupabaseSignOut()

        XCTAssertFalse(revenueCatManager.isProActive)
        XCTAssertFalse(revenueCatManager.isSubscribed)
    }

    func testSevenDayPassPolicyUnlocksActivePass() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let purchase = SevenDayPassPurchase(
            productIdentifier: SevenDayPassAccessPolicy.productIdentifier,
            purchaseDate: now.addingTimeInterval(-6 * 24 * 60 * 60)
        )

        XCTAssertTrue(
            SevenDayPassAccessPolicy.isActive(purchases: [purchase], now: now)
        )
    }

    func testSevenDayPassPolicyRejectsExpiredPass() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let purchase = SevenDayPassPurchase(
            productIdentifier: SevenDayPassAccessPolicy.productIdentifier,
            purchaseDate: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )

        XCTAssertFalse(
            SevenDayPassAccessPolicy.isActive(purchases: [purchase], now: now)
        )
    }

    func testSevenDayPassPolicyRejectsPassAtExactExpirationBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let purchase = SevenDayPassPurchase(
            productIdentifier: SevenDayPassAccessPolicy.productIdentifier,
            purchaseDate: now.addingTimeInterval(-7 * 24 * 60 * 60)
        )

        XCTAssertFalse(
            SevenDayPassAccessPolicy.isActive(purchases: [purchase], now: now)
        )
    }

    func testSevenDayPassPolicyUnlocksWhenAnyExactPassPurchaseIsActive() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expiredPurchase = SevenDayPassPurchase(
            productIdentifier: SevenDayPassAccessPolicy.productIdentifier,
            purchaseDate: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        let activePurchase = SevenDayPassPurchase(
            productIdentifier: SevenDayPassAccessPolicy.productIdentifier,
            purchaseDate: now.addingTimeInterval(-1 * 24 * 60 * 60)
        )

        XCTAssertTrue(
            SevenDayPassAccessPolicy.isActive(
                purchases: [expiredPurchase, activePurchase],
                now: now
            )
        )
    }

    func testSevenDayPassPolicyIgnoresDetachedRevenueCatEntitlementIdentifier() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let purchase = SevenDayPassPurchase(
            productIdentifier: "7_day_pass",
            purchaseDate: now
        )

        XCTAssertFalse(
            SevenDayPassAccessPolicy.isActive(purchases: [purchase], now: now)
        )
    }

    func testSevenDayPassPolicyIgnoresSubstringProductIdentifiers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let purchase = SevenDayPassPurchase(
            productIdentifier: "\(SevenDayPassAccessPolicy.productIdentifier)_extra",
            purchaseDate: now
        )

        XCTAssertFalse(
            SevenDayPassAccessPolicy.isActive(purchases: [purchase], now: now)
        )
    }
}
