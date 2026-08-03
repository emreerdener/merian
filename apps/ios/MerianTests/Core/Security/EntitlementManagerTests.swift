import XCTest
@testable import Merian

@MainActor
final class EntitlementManagerTests: XCTestCase {
    private let userID = UUID(uuidString: "00000000-0000-4000-8000-000000000123")!

    override func setUp() async throws {
        RevenueCatManager.shared.isSubscribed = false
        EntitlementManager.shared.resetForTesting(userID: userID)
    }

    override func tearDown() async throws {
        EntitlementManager.shared.resetForTesting()
        RevenueCatManager.shared.isSubscribed = false
        RevenueCatManager.shared.synchronizeFunctionalEntitlement()
    }

    func testComplimentaryAccessRequiresCurrentLaunchVerification() throws {
        XCTAssertFalse(EntitlementManager.shared.isVerifiedForCurrentLaunch)
        XCTAssertFalse(RevenueCatManager.shared.isProActive)

        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 2,
            available: 2,
            version: 5
        ), for: userID))

        XCTAssertTrue(EntitlementManager.shared.hasVerifiedComplimentaryAccess)
        XCTAssertTrue(RevenueCatManager.shared.isProActive)
        XCTAssertTrue(RevenueCatManager.shared.canStartProScan)

        EntitlementManager.shared.resetForTesting(userID: userID)
        XCTAssertFalse(EntitlementManager.shared.isVerifiedForCurrentLaunch)
        XCTAssertFalse(RevenueCatManager.shared.isProActive)
    }

    func testActiveHoldPreservesFunctionalProButCannotFundAnotherScan() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 0,
            inFlight: 1,
            version: 6
        ), for: userID))

        XCTAssertTrue(RevenueCatManager.shared.isProActive)
        XCTAssertFalse(RevenueCatManager.shared.canStartProScan)
    }

    func testServerVerifiedLegacyTrialRemainsFunctionalBeforeCutover() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_trial",
            tier: "pro",
            remaining: 3,
            available: 3,
            version: 4
        ), for: userID))

        XCTAssertTrue(RevenueCatManager.shared.isProActive)
        XCTAssertTrue(RevenueCatManager.shared.canStartProScan)
    }

    func testStaleResponseCannotRestoreBalance() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 9
        ), for: userID))
        XCTAssertFalse(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 3,
            available: 3,
            version: 8
        ), for: userID))
        XCTAssertEqual(EntitlementManager.shared.scansRemaining, 1)
        XCTAssertEqual(EntitlementManager.shared.entitlementVersion, 9)
    }

    func testScanMetadataFromPreviousAccountIsRejected() throws {
        let otherUserID = UUID(uuidString: "00000000-0000-4000-8000-000000000999")!
        let data = try JSONSerialization.data(withJSONObject: [
            "user_id": otherUserID.uuidString.lowercased(),
            "plan_used": "pro_complimentary",
            "credit_consumed": false,
            "entitlement_after": [
                "current_plan": "pro_complimentary",
                "current_tier": "pro",
                "is_paid": false,
                "scans_remaining": 3,
                "scans_available_to_start": 3,
                "in_flight_count": 0,
                "entitlement_version": 99
            ]
        ])
        let metadata = try JSONDecoder().decode(ScanEntitlementMetadataDTO.self, from: data)

        XCTAssertFalse(EntitlementManager.shared.apply(metadata))
        XCTAssertEqual(EntitlementManager.shared.entitlementVersion, 0)
    }

    func testScanMetadataWaitsForCurrentLaunchBaselineBeforeApplying() throws {
        let metadata = try scanMetadata(
            plan: "free",
            tier: "free",
            remaining: 0,
            available: 0,
            version: 10
        )

        XCTAssertFalse(EntitlementManager.shared.apply(metadata))
        XCTAssertFalse(EntitlementManager.shared.isVerifiedForCurrentLaunch)
        XCTAssertEqual(EntitlementManager.shared.entitlementVersion, 0)
        XCTAssertFalse(RevenueCatManager.shared.isProActive)

        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 0,
            inFlight: 1,
            version: 9
        ), for: userID))

        XCTAssertTrue(EntitlementManager.shared.isVerifiedForCurrentLaunch)
        XCTAssertEqual(EntitlementManager.shared.entitlementVersion, 10)
        XCTAssertTrue(EntitlementManager.shared.isComplimentaryExhausted)
        XCTAssertFalse(RevenueCatManager.shared.isProActive)
    }

    func testBufferedStaleReplayCannotOverrideCurrentLaunchBaseline() throws {
        XCTAssertFalse(EntitlementManager.shared.apply(try scanMetadata(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 3,
            available: 3,
            version: 8
        )))

        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 9
        ), for: userID))
        XCTAssertEqual(EntitlementManager.shared.scansRemaining, 1)
        XCTAssertEqual(EntitlementManager.shared.entitlementVersion, 9)
    }

    func testThirdResultExhaustsNewActionsWithoutRemovingResultState() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "free",
            tier: "free",
            remaining: 0,
            available: 0,
            version: 12
        ), for: userID))
        XCTAssertTrue(EntitlementManager.shared.isComplimentaryExhausted)
        XCTAssertFalse(RevenueCatManager.shared.isProActive)
    }

    func testPaidRevenueCatAccessRemainsAvailableWithoutServerProof() {
        RevenueCatManager.shared.isSubscribed = true
        RevenueCatManager.shared.synchronizeFunctionalEntitlement()
        XCTAssertFalse(EntitlementManager.shared.isVerifiedForCurrentLaunch)
        XCTAssertTrue(RevenueCatManager.shared.isProActive)
        XCTAssertTrue(RevenueCatManager.shared.canStartProScan)
    }

    private func snapshot(
        plan: String,
        tier: String,
        remaining: Int,
        available: Int,
        inFlight: Int = 0,
        version: Int
    ) throws -> EntitlementSnapshotDTO {
        let data = try JSONSerialization.data(withJSONObject: [
            "current_plan": plan,
            "current_tier": tier,
            "is_paid": plan == "pro_paid",
            "scans_remaining": remaining,
            "scans_available_to_start": available,
            "in_flight_count": inFlight,
            "entitlement_version": version
        ])
        return try JSONDecoder().decode(EntitlementSnapshotDTO.self, from: data)
    }

    private func scanMetadata(
        plan: String,
        tier: String,
        remaining: Int,
        available: Int,
        inFlight: Int = 0,
        version: Int
    ) throws -> ScanEntitlementMetadataDTO {
        let data = try JSONSerialization.data(withJSONObject: [
            "user_id": userID.uuidString.lowercased(),
            "plan_used": "pro_complimentary",
            "credit_consumed": plan == "free",
            "entitlement_after": [
                "current_plan": plan,
                "current_tier": tier,
                "is_paid": plan == "pro_paid",
                "scans_remaining": remaining,
                "scans_available_to_start": available,
                "in_flight_count": inFlight,
                "entitlement_version": version
            ]
        ])
        return try JSONDecoder().decode(ScanEntitlementMetadataDTO.self, from: data)
    }
}
