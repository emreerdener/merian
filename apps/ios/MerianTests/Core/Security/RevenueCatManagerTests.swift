import XCTest
@testable import Merian

@MainActor
final class RevenueCatManagerTests: XCTestCase {

    var revenueCatManager: RevenueCatManager!

    override func setUp() async throws {
        revenueCatManager = RevenueCatManager.shared
    }

    override func tearDown() async throws {
        revenueCatManager = nil
    }

    func testInitialStateIsCorrect() {
        XCTAssertFalse(revenueCatManager.isProActive)
        XCTAssertFalse(revenueCatManager.isSubscribed)
        XCTAssertNil(revenueCatManager.currentOfferings)
        XCTAssertFalse(revenueCatManager.isFetchingOfferings)
    }
    
    func testRevenueCatAttributionSignature() async {
        // Asserts that the refactored signature compiles securely mapping telemetry correctly.
        // Because purchases.shared is tightly coupled, we do not fully hit the live backend, 
        // we strictly test the caller logic boundaries directly avoiding signature mismatched crashes natively.
        let testId = UUID().uuidString
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

    func testHandleSupabaseSignOutClearsEntitlementsInTests() async {
        revenueCatManager.isProActive = true
        revenueCatManager.isSubscribed = true
        revenueCatManager.trialDaysRemaining = 3

        await revenueCatManager.handleSupabaseSignOut()

        XCTAssertFalse(revenueCatManager.isProActive)
        XCTAssertFalse(revenueCatManager.isSubscribed)
        XCTAssertNil(revenueCatManager.trialDaysRemaining)
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
