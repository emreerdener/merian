import Foundation
@testable import Merian
import XCTest

@MainActor
final class RevenueCatIdentityCoordinatorTests: XCTestCase {
    func testReplacementWaitsForPriorLinkAndRejectsItsStaleCommit() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let firstRequest = request(appUserID: "first")
        let secondRequest = request(appUserID: "second")
        let gate = RevenueCatIdentityLinkGate()
        let firstStarted = expectation(description: "First link started")
        let replacementScheduled = expectation(
            description: "Replacement link scheduled"
        )
        var events: [String] = []
        var firstCommitAccepted: Bool?
        var secondCommitAccepted: Bool?
        var secondStarted = false

        let firstTask = Task { @MainActor in
            await coordinator.link(
                firstRequest,
                resetPaidReadiness: {},
                operation: { context in
                    events.append("first-started")
                    firstStarted.fulfill()
                    await gate.wait()
                    events.append("first-resumed")
                    firstCommitAccepted = coordinator.commit(context)
                }
            )
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        let secondTask = Task { @MainActor in
            await coordinator.link(
                secondRequest,
                resetPaidReadiness: {
                    replacementScheduled.fulfill()
                },
                operation: { context in
                    secondStarted = true
                    events.append("second-started")
                    secondCommitAccepted = coordinator.commit(context)
                }
            )
        }
        await fulfillment(of: [replacementScheduled], timeout: 1)
        XCTAssertFalse(secondStarted)

        gate.open()
        await firstTask.value
        await secondTask.value

        XCTAssertEqual(firstCommitAccepted, false)
        XCTAssertEqual(secondCommitAccepted, true)
        XCTAssertEqual(
            events,
            ["first-started", "first-resumed", "second-started"]
        )
        XCTAssertEqual(coordinator.linkedAppUserID, secondRequest.appUserID)
        XCTAssertEqual(coordinator.linkedAuthUserID, secondRequest.authUserID)
    }

    func testResolutionInvalidatesCancellationUncooperativeLink() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let request = request(appUserID: "active")
        let gate = RevenueCatIdentityLinkGate()
        let started = expectation(description: "Link started")
        var commitAccepted: Bool?

        let task = Task { @MainActor in
            await coordinator.link(
                request,
                resetPaidReadiness: {},
                operation: { context in
                    started.fulfill()
                    await gate.wait()
                    commitAccepted = coordinator.commit(context)
                }
            )
        }
        await fulfillment(of: [started], timeout: 1)

        coordinator.beginPurchaseIdentityResolution()
        XCTAssertFalse(coordinator.accountGrantsAllowed)
        XCTAssertNil(coordinator.linkedAuthUserID)

        gate.open()
        await task.value

        XCTAssertEqual(commitAccepted, false)
        XCTAssertNil(coordinator.linkedAppUserID)
        XCTAssertNil(coordinator.linkedBindingGeneration)
    }

    func testSameProviderRebindRetainsProviderIDAndClosesAccountState() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let firstRequest = request(
            appUserID: "shared-principal",
            authUserID: UUID(),
            bindingGeneration: 3,
            accountGrantsAllowed: true,
            usesStablePurchasePrincipal: true
        )
        await commit(firstRequest, on: coordinator)

        let secondRequest = request(
            appUserID: firstRequest.appUserID,
            authUserID: UUID(),
            bindingGeneration: 4,
            accountGrantsAllowed: false,
            usesStablePurchasePrincipal: true
        )
        var resetCount = 0
        await coordinator.link(
            secondRequest,
            resetPaidReadiness: { resetCount += 1 },
            operation: { context in
                XCTAssertEqual(
                    coordinator.linkedAppUserID,
                    firstRequest.appUserID
                )
                XCTAssertNil(coordinator.linkedAuthUserID)
                XCTAssertNil(coordinator.linkedBindingGeneration)
                XCTAssertNil(coordinator.linkedAccountKind)
                XCTAssertFalse(coordinator.accountGrantsAllowed)
                XCTAssertTrue(coordinator.commit(context))
            }
        )

        XCTAssertEqual(resetCount, 1)
        XCTAssertEqual(coordinator.linkedAuthUserID, secondRequest.authUserID)
        XCTAssertEqual(coordinator.linkedBindingGeneration, 4)
        XCTAssertFalse(coordinator.accountGrantsAllowed)

        await coordinator.link(
            secondRequest,
            resetPaidReadiness: { resetCount += 1 },
            operation: { context in
                XCTAssertTrue(coordinator.commit(context))
            }
        )
        XCTAssertEqual(resetCount, 1)
    }

    func testHandoffClosesPurchaseReadinessWhilePending() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let request = request(
            appUserID: "stable-principal",
            accountGrantsAllowed: true,
            usesStablePurchasePrincipal: true
        )
        await commit(request, on: coordinator)

        XCTAssertTrue(coordinator.isProviderMutationIdentityReady(
            providerIdentityReady: true
        ))
        XCTAssertTrue(coordinator.isPurchaseIdentityReady(
            providerIdentityReady: true
        ))

        coordinator.setPurchaseIdentityHandoffPending(true)
        XCTAssertFalse(coordinator.accountGrantsAllowed)
        XCTAssertFalse(coordinator.isPurchaseIdentityReady(
            providerIdentityReady: true
        ))

        coordinator.setPurchaseIdentityHandoffPending(false)
        XCTAssertTrue(coordinator.isPurchaseIdentityReady(
            providerIdentityReady: true
        ))

        coordinator.beginPurchaseIdentityResolution()
        XCTAssertFalse(coordinator.isProviderMutationIdentityReady(
            providerIdentityReady: true
        ))
        XCTAssertFalse(coordinator.isPurchaseIdentityReady(
            providerIdentityReady: true
        ))
    }

    func testProviderOperationContextChangesAcrossEveryReadinessFence() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let linkedRequest = request(
            appUserID: "shared-principal",
            accountGrantsAllowed: true,
            usesStablePurchasePrincipal: true
        )
        await commit(linkedRequest, on: coordinator)

        let initial = providerOperationContext(
            appUserID: linkedRequest.appUserID,
            coordinator: coordinator
        )
        coordinator.beginPurchaseIdentityResolution()
        let resolving = providerOperationContext(
            appUserID: linkedRequest.appUserID,
            coordinator: coordinator
        )
        XCTAssertNotEqual(resolving, initial)

        await commit(linkedRequest, on: coordinator)
        let rebound = providerOperationContext(
            appUserID: linkedRequest.appUserID,
            coordinator: coordinator
        )
        XCTAssertNotEqual(rebound, resolving)

        coordinator.setPurchaseIdentityHandoffPending(true)
        let handoff = providerOperationContext(
            appUserID: linkedRequest.appUserID,
            coordinator: coordinator
        )
        XCTAssertNotEqual(handoff, rebound)

        coordinator.setPurchaseIdentityHandoffPending(false)
        XCTAssertEqual(
            providerOperationContext(
                appUserID: linkedRequest.appUserID,
                coordinator: coordinator
            ),
            handoff
        )
    }

    func testPendingHandoffDominatesGrantsCommittedByInFlightLink() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let request = request(
            appUserID: "stable-principal",
            accountGrantsAllowed: true,
            usesStablePurchasePrincipal: true
        )
        let gate = RevenueCatIdentityLinkGate()
        let started = expectation(description: "Identity link started")

        let task = Task { @MainActor in
            await coordinator.link(
                request,
                resetPaidReadiness: {},
                operation: { context in
                    started.fulfill()
                    await gate.wait()
                    XCTAssertTrue(coordinator.commit(context))
                }
            )
        }
        await fulfillment(of: [started], timeout: 1)

        coordinator.setPurchaseIdentityHandoffPending(true)
        gate.open()
        await task.value

        XCTAssertEqual(coordinator.linkedAppUserID, request.appUserID)
        XCTAssertFalse(coordinator.accountGrantsAllowed)
        XCTAssertFalse(coordinator.isPurchaseIdentityReady(
            providerIdentityReady: true
        ))

        coordinator.setPurchaseIdentityHandoffPending(false)
        XCTAssertFalse(coordinator.accountGrantsAllowed)
    }

    func testCompletedHandoffStillFencesGrantsCapturedBeforeItBegan() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let request = request(
            appUserID: "stable-principal",
            accountGrantsAllowed: true,
            usesStablePurchasePrincipal: true
        )
        let gate = RevenueCatIdentityLinkGate()
        let started = expectation(description: "Identity link started")

        let task = Task { @MainActor in
            await coordinator.link(
                request,
                resetPaidReadiness: {},
                operation: { context in
                    started.fulfill()
                    await gate.wait()
                    XCTAssertTrue(coordinator.commit(context))
                }
            )
        }
        await fulfillment(of: [started], timeout: 1)

        coordinator.setPurchaseIdentityHandoffPending(true)
        coordinator.setPurchaseIdentityHandoffPending(false)
        gate.open()
        await task.value

        XCTAssertEqual(coordinator.linkedAppUserID, request.appUserID)
        XCTAssertFalse(coordinator.accountGrantsAllowed)
    }

    func testPostFenceBindingMayCommitGrantsAfterHandoffClears() async {
        let coordinator = RevenueCatIdentityCoordinator()
        let request = request(
            appUserID: "stable-principal",
            accountGrantsAllowed: true,
            usesStablePurchasePrincipal: true
        )
        let gate = RevenueCatIdentityLinkGate()
        let started = expectation(description: "Identity link started")

        coordinator.setPurchaseIdentityHandoffPending(true)
        let task = Task { @MainActor in
            await coordinator.link(
                request,
                resetPaidReadiness: {},
                operation: { context in
                    started.fulfill()
                    await gate.wait()
                    XCTAssertTrue(coordinator.commit(context))
                }
            )
        }
        await fulfillment(of: [started], timeout: 1)

        coordinator.setPurchaseIdentityHandoffPending(false)
        gate.open()
        await task.value

        XCTAssertEqual(coordinator.linkedAppUserID, request.appUserID)
        XCTAssertTrue(coordinator.accountGrantsAllowed)
    }

    func testSignOutRetainsOnlyStableProviderIdentity() async {
        let stableCoordinator = RevenueCatIdentityCoordinator()
        await commit(
            request(
                appUserID: "stable-principal",
                usesStablePurchasePrincipal: true
            ),
            on: stableCoordinator
        )

        stableCoordinator.beginPurchaseIdentityResolution()
        stableCoordinator.clearProviderIdentityForSignOutIfLegacy()

        XCTAssertEqual(
            stableCoordinator.linkedAppUserID,
            "stable-principal"
        )
        XCTAssertNil(stableCoordinator.linkedAuthUserID)

        let legacyCoordinator = RevenueCatIdentityCoordinator()
        await commit(
            request(
                appUserID: "legacy-user",
                usesStablePurchasePrincipal: false
            ),
            on: legacyCoordinator
        )

        legacyCoordinator.beginPurchaseIdentityResolution()
        legacyCoordinator.clearProviderIdentityForSignOutIfLegacy()

        XCTAssertNil(legacyCoordinator.linkedAppUserID)
        XCTAssertNil(legacyCoordinator.linkedAuthUserID)
    }

    private func commit(
        _ request: RevenueCatIdentityCoordinator.Request,
        on coordinator: RevenueCatIdentityCoordinator
    ) async {
        await coordinator.link(
            request,
            resetPaidReadiness: {},
            operation: { context in
                XCTAssertTrue(coordinator.commit(context))
            }
        )
    }

    private func providerOperationContext(
        appUserID: String,
        coordinator: RevenueCatIdentityCoordinator
    ) -> RevenueCatProviderOperationContext {
        coordinator.providerOperationContext(appUserID: appUserID)
    }

    private func request(
        appUserID: String,
        authUserID: UUID = UUID(),
        bindingGeneration: Int64 = 1,
        accountKind: String = "authenticated",
        accountGrantsAllowed: Bool = true,
        usesStablePurchasePrincipal: Bool = false
    ) -> RevenueCatIdentityCoordinator.Request {
        RevenueCatIdentityCoordinator.Request(
            appUserID: appUserID,
            authUserID: authUserID,
            bindingGeneration: bindingGeneration,
            accountKind: accountKind,
            accountGrantsAllowed: accountGrantsAllowed,
            usesStablePurchasePrincipal: usesStablePurchasePrincipal
        )
    }
}

@MainActor
private final class RevenueCatIdentityLinkGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
