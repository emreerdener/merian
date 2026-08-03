@testable import Merian
import XCTest

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

    func testOneVerifiedCreditCreatesOneLocalComplimentaryReservation() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 20
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000201"
        let second = "00000000-0000-4000-8000-000000000202"

        let firstFunding = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )
        let secondFunding = EntitlementManager.shared.claimFunding(
            scanId: second,
            flashFallbackEligible: true
        )

        XCTAssertEqual(firstFunding?.source, .complimentaryPro)
        XCTAssertEqual(secondFunding?.source, .deferredFlash)
        XCTAssertEqual(secondFunding?.blockerScanIds, [first])
        XCTAssertEqual(
            EntitlementManager.shared.locallyAvailableComplimentaryCredits,
            0
        )
        XCTAssertFalse(
            EntitlementManager.shared.fundingAllowsDispatch(scanId: second)
        )
    }

    func testLegacyJobConservativelyReservesComplimentaryCapacity() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 20
        ), for: userID))
        let legacy = "00000000-0000-4000-8000-000000000222"
        let later = "00000000-0000-4000-8000-000000000223"
        EntitlementManager.shared.restoreLegacyPotentialBlocker(
            scanId: legacy,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let funding = EntitlementManager.shared.claimFunding(
            scanId: later,
            flashFallbackEligible: true
        )

        XCTAssertEqual(
            EntitlementManager.shared.locallyAvailableComplimentaryCredits,
            0
        )
        XCTAssertEqual(funding?.source, .deferredFlash)
        XCTAssertEqual(funding?.blockerScanIds, [legacy])
    }

    func testProvenLocalFailureReleasesDeferredDependents() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 20
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000224"
        let second = "00000000-0000-4000-8000-000000000225"
        _ = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )
        _ = EntitlementManager.shared.claimFunding(
            scanId: second,
            flashFallbackEligible: true
        )

        EntitlementManager.shared.releaseFundingAfterProvenLocalFailure(
            scanId: first
        )
        let changes = EntitlementManager.shared.resolveDeferredFunding()

        XCTAssertEqual(changes.first?.source, .complimentaryPro)
        XCTAssertTrue(
            EntitlementManager.shared.fundingAllowsDispatch(scanId: second)
        )
    }

    func testSuccessfulReleasedComplimentaryHoldIsNotRecordedAsConsumed() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 20
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000226"
        let second = "00000000-0000-4000-8000-000000000227"
        _ = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )
        _ = EntitlementManager.shared.claimFunding(
            scanId: second,
            flashFallbackEligible: true
        )

        EntitlementManager.shared.recordCompletedFunding(
            planUsed: "pro_complimentary",
            creditConsumed: false,
            scanId: first
        )
        let changes = EntitlementManager.shared.resolveDeferredFunding()

        XCTAssertEqual(changes.first?.source, .complimentaryPro)
    }

    func testPaidAccessReclassifiesDeferredScanWithoutWaitingForBlocker() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 20
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000229"
        let second = "00000000-0000-4000-8000-000000000230"
        _ = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )
        _ = EntitlementManager.shared.claimFunding(
            scanId: second,
            flashFallbackEligible: true
        )

        RevenueCatManager.shared.isSubscribed = true
        let changes = EntitlementManager.shared.resolveDeferredFunding()

        XCTAssertEqual(changes.first?.source, .paidPro)
        XCTAssertTrue(
            EntitlementManager.shared.fundingAllowsDispatch(scanId: second)
        )
    }

    func testConsumedStatusKeepsCapacityReservedUntilEntitlementRefresh() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 20
        ), for: userID))
        let legacy = "00000000-0000-4000-8000-000000000228"
        EntitlementManager.shared.restoreLegacyPotentialBlocker(
            scanId: legacy,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        EntitlementManager.shared.applyComplimentaryState(
            .consumed,
            scanId: legacy,
            terminalized: true
        )

        XCTAssertTrue(
            EntitlementManager.shared.needsTerminalSettlementEntitlementRefresh
        )
        XCTAssertEqual(
            EntitlementManager.shared.locallyAvailableComplimentaryCredits,
            0
        )

        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "free",
            tier: "free",
            remaining: 0,
            available: 0,
            version: 21
        ), for: userID))
        EntitlementManager.shared
            .confirmTerminalSettlementsAfterEntitlementRefresh()
        XCTAssertFalse(
            EntitlementManager.shared.needsTerminalSettlementEntitlementRefresh
        )
    }

    func testMixedCaptureWithoutComplimentaryCapacityIsNotAdmitted() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "free",
            tier: "free",
            remaining: 0,
            available: 0,
            version: 21
        ), for: userID))

        XCTAssertNil(EntitlementManager.shared.claimFunding(
            scanId: "00000000-0000-4000-8000-000000000203",
            flashFallbackEligible: false
        ))
    }

    func testHeldBlockerMakesDeferredFlashDispatchable() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 22
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000204"
        let second = "00000000-0000-4000-8000-000000000205"
        _ = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )
        _ = EntitlementManager.shared.claimFunding(
            scanId: second,
            flashFallbackEligible: true
        )

        EntitlementManager.shared.applyComplimentaryState(
            .held,
            scanId: first,
            terminalized: false
        )
        let changes = EntitlementManager.shared.resolveDeferredFunding()

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.source, .immediateFlash)
        XCTAssertTrue(
            EntitlementManager.shared.fundingAllowsDispatch(scanId: second)
        )
    }

    func testHeldStateCannotReopenCapacityInAStaleSnapshot() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 22
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000214"
        let later = "00000000-0000-4000-8000-000000000215"
        _ = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )

        EntitlementManager.shared.applyComplimentaryState(
            .held,
            scanId: first,
            terminalized: false
        )
        let laterFunding = EntitlementManager.shared.claimFunding(
            scanId: later,
            flashFallbackEligible: true
        )

        XCTAssertEqual(
            EntitlementManager.shared.locallyAvailableComplimentaryCredits,
            0
        )
        XCTAssertEqual(laterFunding?.source, .immediateFlash)
    }

    func testReleasedBlockerStaysDeferredUntilEarlierJobIsTerminal() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 23
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000218"
        let second = "00000000-0000-4000-8000-000000000219"
        _ = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )
        _ = EntitlementManager.shared.claimFunding(
            scanId: second,
            flashFallbackEligible: true
        )

        EntitlementManager.shared.applyComplimentaryState(
            .released,
            scanId: first,
            terminalized: false
        )

        XCTAssertFalse(EntitlementManager.shared.hasReleasedDeferredBlocker)
        XCTAssertTrue(EntitlementManager.shared.resolveDeferredFunding().isEmpty)
        XCTAssertFalse(
            EntitlementManager.shared.fundingAllowsDispatch(scanId: second)
        )
        XCTAssertEqual(
            EntitlementManager.shared.locallyAvailableComplimentaryCredits,
            0
        )
    }

    func testReleasedBlockerCanPromoteDeferredScanAfterRefresh() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 23
        ), for: userID))
        let first = "00000000-0000-4000-8000-000000000206"
        let second = "00000000-0000-4000-8000-000000000207"
        _ = EntitlementManager.shared.claimFunding(
            scanId: first,
            flashFallbackEligible: true
        )
        _ = EntitlementManager.shared.claimFunding(
            scanId: second,
            flashFallbackEligible: true
        )
        EntitlementManager.shared.applyComplimentaryState(
            .released,
            scanId: first,
            terminalized: true
        )
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 24
        ), for: userID))

        let changes = EntitlementManager.shared.resolveDeferredFunding()
        XCTAssertEqual(changes.first?.source, .complimentaryPro)
    }

    func testTerminalReleasedLegacyBlockerDoesNotStallDeferredScan() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "free",
            tier: "free",
            remaining: 0,
            available: 0,
            version: 25
        ), for: userID))
        let legacy = "00000000-0000-4000-8000-000000000220"
        let later = "00000000-0000-4000-8000-000000000221"
        EntitlementManager.shared.restoreLegacyPotentialBlocker(
            scanId: legacy,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let deferred = EntitlementManager.shared.claimFunding(
            scanId: later,
            flashFallbackEligible: true
        )
        XCTAssertEqual(deferred?.source, .deferredFlash)

        EntitlementManager.shared.applyComplimentaryState(
            .released,
            scanId: legacy,
            terminalized: true
        )
        let changes = EntitlementManager.shared.resolveDeferredFunding()

        XCTAssertEqual(changes.first?.source, .immediateFlash)
        XCTAssertTrue(
            EntitlementManager.shared.fundingAllowsDispatch(scanId: later)
        )
    }

    func testGenerationRemovalPreservesFundingMetadata() throws {
        let generation = UUID()
        let funding = ScanFundingReservation(
            accountId: userID,
            scanId: "00000000-0000-4000-8000-000000000208",
            source: .complimentaryPro
        )
        let metadata = try XCTUnwrap(OfflineScanJobMetadataContract.json(
            generation: generation,
            funding: funding
        ))

        let handedOff = InferenceGenerationMetadataContract.removing(
            generation,
            from: metadata
        )
        XCTAssertNil(InferenceGenerationMetadataContract.generation(
            in: handedOff
        ))
        XCTAssertEqual(
            OfflineScanJobMetadataContract.funding(in: handedOff),
            funding
        )
    }

    func testDurableFundingReleasePreservesGenerationAndRequiresFreshClaim() throws {
        let generation = UUID()
        let original = ScanFundingReservation(
            accountId: userID,
            scanId: "00000000-0000-4000-8000-000000000231",
            source: .complimentaryPro
        )
        let metadata = try XCTUnwrap(OfflineScanJobMetadataContract.json(
            generation: generation,
            funding: original
        ))

        let released = try XCTUnwrap(
            OfflineScanJobMetadataContract.markingFundingReleased(in: metadata)
        )
        XCTAssertNil(OfflineScanJobMetadataContract.funding(in: released))
        XCTAssertTrue(
            OfflineScanJobMetadataContract.fundingWasReleased(in: released)
        )
        XCTAssertEqual(
            InferenceGenerationMetadataContract.generation(in: released),
            generation
        )

        let replacement = ScanFundingReservation(
            accountId: userID,
            scanId: original.scanId,
            source: .immediateFlash
        )
        let reclaimed = OfflineScanJobMetadataContract.settingFunding(
            replacement,
            in: released
        )
        XCTAssertEqual(
            OfflineScanJobMetadataContract.funding(in: reclaimed),
            replacement
        )
        XCTAssertFalse(
            OfflineScanJobMetadataContract.fundingWasReleased(in: reclaimed)
        )
    }

    func testRelaunchRestoresDeferredFundingOrderFromMetadata() throws {
        let first = "00000000-0000-4000-8000-000000000216"
        let second = "00000000-0000-4000-8000-000000000217"
        let earlier = ScanFundingReservation(
            accountId: userID,
            scanId: first,
            source: .complimentaryPro,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let deferred = ScanFundingReservation(
            accountId: userID,
            scanId: second,
            source: .deferredFlash,
            blockerScanIds: [first],
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let metadata = try XCTUnwrap(OfflineScanJobMetadataContract.json(
            generation: nil,
            funding: deferred
        ))

        EntitlementManager.shared.resetForTesting(userID: userID)
        EntitlementManager.shared.restoreFundingReservation(earlier)
        EntitlementManager.shared.restoreFundingReservation(try XCTUnwrap(
            OfflineScanJobMetadataContract.funding(in: metadata)
        ))

        XCTAssertEqual(EntitlementManager.shared.fundingBlockerScanIds, [first])
        XCTAssertFalse(
            EntitlementManager.shared.fundingAllowsDispatch(scanId: second)
        )
        XCTAssertEqual(
            EntitlementManager.shared.fundingPriority(scanId: first),
            0
        )
    }

    func testPaymentRequiredInvalidatesComplimentaryProof() throws {
        XCTAssertTrue(EntitlementManager.shared.apply(try snapshot(
            plan: "pro_complimentary",
            tier: "pro",
            remaining: 1,
            available: 1,
            version: 25
        ), for: userID))
        EntitlementManager.shared
            .invalidateComplimentaryProofAfterPaymentRequired()
        XCTAssertFalse(EntitlementManager.shared.isVerifiedForCurrentLaunch)
        XCTAssertFalse(EntitlementManager.shared.canStartProFundedScan)
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
