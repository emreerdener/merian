@testable import Merian
import XCTest
import SwiftData

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

    func testDeferredResolutionRequiresEligibleReservationAndEveryBlocker() {
        let manager = EntitlementManager.shared
        let reservation = ScanFundingReservation(accountId: userID, scanId: "waiting",
            source: .deferredFlash, blockerScanIds: ["native-blocker"])
        manager.restoreFundingReservation(reservation)
        RevenueCatManager.shared.isSubscribed = true
        XCTAssertTrue(manager.resolveDeferredFunding(eligibleLegacyScanIDs: ["waiting"]).isEmpty)
        XCTAssertTrue(manager.resolveDeferredFunding(eligibleLegacyScanIDs: ["native-blocker"]).isEmpty)
        XCTAssertEqual(manager.fundingReservation(scanId: "waiting"), reservation)
        XCTAssertEqual(manager.resolveDeferredFunding(eligibleLegacyScanIDs: ["waiting", "native-blocker"]).first?.source, .paidPro)
    }

    func testExcludedTerminalSettlementRetainsCapacityAndUnknownOwnershipOverridesStaleRelease() throws {
        let manager = EntitlementManager.shared
        XCTAssertTrue(manager.apply(try snapshot(plan: "pro_complimentary", tier: "pro",
            remaining: 1, available: 1, version: 20), for: userID))
        manager.restoreLegacyPotentialBlocker(scanId: "native", createdAt: Date())
        manager.applyComplimentaryState(.consumed, scanId: "native", terminalized: true)
        manager.confirmTerminalSettlementsAfterEntitlementRefresh(eligibleLegacyScanIDs: [])
        XCTAssertTrue(manager.needsTerminalSettlementEntitlementRefresh)
        XCTAssertEqual(manager.locallyAvailableComplimentaryCredits, 0)
        manager.applyComplimentaryState(.released, scanId: "native", terminalized: true)
        XCTAssertEqual(manager.locallyAvailableComplimentaryCredits, 1)
        manager.restoreLegacyPotentialBlocker(scanId: "native", createdAt: Date(), unresolvedOwnership: true)
        XCTAssertEqual(manager.locallyAvailableComplimentaryCredits, 0)
        let waiting = try XCTUnwrap(manager.claimFunding(scanId: "waiting", flashFallbackEligible: true))
        XCTAssertEqual(waiting.source, .deferredFlash)
        XCTAssertTrue(waiting.blockerScanIds.contains("native"))
    }

    func testNativeFundingReceiptBlocksLegacyReconciliationWithoutNetworkOrRewrite() async throws {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let manager = OfflineQueueManager.shared, old = manager.modelContext
        defer { manager.modelContext = old }
        manager.modelContext = context
        let entitlement = EntitlementManager.shared
        XCTAssertTrue(entitlement.apply(try snapshot(plan: "pro_complimentary", tier: "pro",
            remaining: 1, available: 1, version: 20), for: userID))
        let native = ScanFundingReservation(accountId: userID, scanId: "native", source: .deferredFlash)
        let legacy = ScanFundingReservation(accountId: userID, scanId: "legacy", source: .deferredFlash,
            blockerScanIds: ["native"])
        var nativeObject = OfflineScanJobMetadataContract.object(from:
            OfflineScanJobMetadataContract.settingFunding(native, in: nil))
        nativeObject["native_receiving_v1"] = [:] as [String: String]
        let metadata = try XCTUnwrap(OfflineScanJobMetadataContract.json(from: nativeObject))
        let nativeJob = OfflineJobRecord(id: "scan-ingestion:native", kind: .scanIngestion,
            subjectId: "native", metadataJSON: metadata)
        let legacyJSON = OfflineScanJobMetadataContract.settingFunding(legacy, in: nil)
        let legacyJob = OfflineJobRecord(id: "scan-ingestion:legacy", kind: .scanIngestion,
            subjectId: "legacy", metadataJSON: legacyJSON)
        context.insert(nativeJob); context.insert(legacyJob); try context.save()
        entitlement.restoreFundingReservation(native)
        manager.restoreFundingReservationsForCurrentAccount()
        XCTAssertEqual(entitlement.locallyAvailableComplimentaryCredits, 0)
        XCTAssertEqual(entitlement.fundingReservation(scanId: "native"), native)
        var lookups = 0, refreshes = 0
        await manager.reconcileLegacyFunding(isCurrent: { true }, lookup: { _ in
            lookups += 1; return [:]
        }, refresh: { refreshes += 1; return true })
        XCTAssertEqual(lookups, 0)
        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(entitlement.fundingReservation(scanId: "native"), native)
        XCTAssertEqual(entitlement.fundingReservation(scanId: "legacy"), legacy)
        XCTAssertEqual(nativeJob.metadataJSON, metadata)
        XCTAssertEqual(legacyJob.metadataJSON, legacyJSON)
        XCTAssertFalse(manager.releaseFundingForProvenPredispatchFailure(scanId: "native"))
        XCTAssertEqual(nativeJob.metadataJSON, metadata)
    }

    func testSessionVerificationAcceptsOnlyExactCurrentAccountGenerationAndRow() {
        let generation = UUID()

        XCTAssertTrue(EntitlementManager.acceptsSessionVerificationResult(
            accountContextIsCurrent: true,
            expectedUserID: userID,
            activeUserID: userID,
            requestGeneration: generation,
            activeGeneration: generation,
            rowCount: 1
        ))
    }

    func testSessionVerificationRejectsStaleOrAmbiguousAccountEvidence() {
        let generation = UUID()
        let otherUserID = UUID()

        XCTAssertFalse(EntitlementManager.acceptsSessionVerificationResult(
            accountContextIsCurrent: false,
            expectedUserID: userID,
            activeUserID: userID,
            requestGeneration: generation,
            activeGeneration: generation,
            rowCount: 1
        ))
        XCTAssertFalse(EntitlementManager.acceptsSessionVerificationResult(
            accountContextIsCurrent: true,
            expectedUserID: userID,
            activeUserID: otherUserID,
            requestGeneration: generation,
            activeGeneration: generation,
            rowCount: 1
        ))
        XCTAssertFalse(EntitlementManager.acceptsSessionVerificationResult(
            accountContextIsCurrent: true,
            expectedUserID: userID,
            activeUserID: userID,
            requestGeneration: generation,
            activeGeneration: UUID(),
            rowCount: 1
        ))
        XCTAssertFalse(EntitlementManager.acceptsSessionVerificationResult(
            accountContextIsCurrent: true,
            expectedUserID: userID,
            activeUserID: userID,
            requestGeneration: generation,
            activeGeneration: generation,
            rowCount: 0
        ))
        XCTAssertFalse(EntitlementManager.acceptsSessionVerificationResult(
            accountContextIsCurrent: true,
            expectedUserID: userID,
            activeUserID: userID,
            requestGeneration: generation,
            activeGeneration: generation,
            rowCount: 2
        ))
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
        let changes = EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs)

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
        let changes = EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs)

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
        let changes = EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs)

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
            .confirmTerminalSettlementsAfterEntitlementRefresh(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs)
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
        let changes = EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs)

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

        XCTAssertFalse(EntitlementManager.shared.needsLegacyFundingRefresh(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs))
        XCTAssertTrue(EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs).isEmpty)
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

        let changes = EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs)
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
        let changes = EntitlementManager.shared.resolveDeferredFunding(eligibleLegacyScanIDs: EntitlementManager.shared.fundingCandidateScanIDs)

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
