import Foundation
import Testing
@testable import Merian

@Suite("Purchase Identity Readiness Coordinator")
@MainActor
struct PurchaseIdentityReadinessCoordinatorTests {
    @Test func testExecutionStopsBeforeAccountWork() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.isTestExecution = true

        let result = await makeCoordinator(harness).repair()

        #expect(!result)
        #expect(harness.accountWorkFinishCount == 0)
        #expect(harness.sdkLoadCount == 0)
    }

    @Test func unreadableJournalPublishesFailClosedFence() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.handoffReadError =
            PurchaseIdentitySessionCoordinatorTestError.failed

        let result = await makeCoordinator(harness).repair()

        #expect(!result)
        #expect(harness.publishedHandoffValues == [true])
        #expect(harness.accountWorkFinishCount == 1)
    }

    @Test func anonymousPendingHandoffUsesCompletionRoute() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness(
            isAnonymous: true
        )
        harness.handoffPending = true

        let result = await makeCoordinator(harness).repair()

        #expect(result)
        #expect(harness.events == ["complete-handoff"])
        #expect(harness.publishedHandoffValues == [true])
        #expect(harness.resolutionCount == 0)
        #expect(harness.accountWorkFinishCount == 1)
    }

    @Test func restoredSourceRetiresHandoffBeforeReadiness() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.handoffPending = true
        harness.clearsHandoffOnAbandonment = true

        let result = await makeCoordinator(harness).repair()

        #expect(result)
        #expect(harness.events == [
            "abandon-handoff",
            "begin-resolution",
            "resolve",
            "link-legacy",
            "begin-entitlement"
        ])
        #expect(harness.publishedHandoffValues == [true, false, false])
        #expect(harness.sdkLoadCount == 2)
    }

    @Test func readyIdentityAndEntitlementAvoidRemoteRepair() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.entitlementReady = true
        let sessionCoordinator = PurchaseIdentitySessionCoordinator()
        sessionCoordinator.recordBinding(.legacyFallback)
        sessionCoordinator.recordLinkedUser(harness.userID)
        harness.providerState = PurchaseIdentityProviderState(
            isIdentityReady: true,
            linkedAuthUserID: harness.userID,
            linkedAccountKind: harness.context.accountKind
        )

        let result = await PurchaseIdentityReadinessCoordinator(
            sessionCoordinator: sessionCoordinator,
            dependencies: harness.dependencies()
        ).repair()

        #expect(result)
        #expect(harness.resolutionCount == 0)
        #expect(!harness.events.contains("begin-entitlement"))
        #expect(harness.sdkLoadCount == 2)
    }

    @Test func staleGenerationAfterEntitlementFailsFinalFence() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.advanceGenerationDuringEntitlement = true

        let result = await makeCoordinator(harness).repair()

        #expect(!result)
        #expect(harness.events.last == "begin-entitlement")
        #expect(harness.sdkLoadCount == 2)
        #expect(harness.accountWorkFinishCount == 1)
    }

    private func makeCoordinator(
        _ harness: PurchaseIdentitySessionCoordinatorHarness
    ) -> PurchaseIdentityReadinessCoordinator {
        PurchaseIdentityReadinessCoordinator(
            sessionCoordinator: PurchaseIdentitySessionCoordinator(),
            dependencies: harness.dependencies()
        )
    }
}
