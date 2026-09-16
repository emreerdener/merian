@testable import Merian
import XCTest

@MainActor
final class AppleRevocationCoordinatorTests: XCTestCase {
    func testNotificationWithoutAppleIdentityPerformsNoLookup() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await Task.yield()

        let requestCount = await harness.lookups.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.diagnostics.isEmpty)
    }

    func testActiveTransitionDefersLookupUntilStableSessionResumes() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity
        harness.hasActiveTransition = true

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await Task.yield()
        let deferredRequestCount = await harness.lookups.requestCount()
        XCTAssertEqual(deferredRequestCount, 0)

        harness.hasActiveTransition = false
        coordinator.resumeDeferredIfNeeded(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        await harness.lookups.resolveNext(with: .authorized)
        await waitUntil { harness.diagnostics.count == 1 }

        XCTAssertEqual(
            harness.diagnostics,
            [.authorizedSessionPreserved]
        )
        XCTAssertEqual(harness.clearCount, 0)
    }

    func testAuthorizedCredentialPreservesCurrentSession() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        await harness.lookups.resolveNext(with: .authorized)
        await waitUntil { harness.diagnostics.count == 1 }

        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertEqual(
            harness.diagnostics,
            [.authorizedSessionPreserved]
        )
    }

    func testEveryUnauthorizedCredentialStateFailsClosed() async {
        for result in [
            AppleCredentialRevocationLookupResult.revoked,
            .notFound,
            .transferred,
            .unknown
        ] {
            let harness = AppleRevocationCoordinatorHarness()
            let coordinator = AppleCredentialRevocationCoordinator()
            harness.currentIdentity = harness.firstIdentity

            coordinator.handleRevocationNotification(
                dependencies: harness.dependencies()
            )
            await harness.lookups.waitUntilRequestCount(1)
            await harness.lookups.resolveNext(with: result)
            await waitUntil { harness.clearCount == 1 }

            XCTAssertNil(harness.currentIdentity)
            XCTAssertEqual(
                harness.diagnostics,
                [.unauthorizedCredentialClearingLocalSession]
            )
        }
    }

    func testLookupFailureFailsClosedWithDistinctDiagnostic() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        await harness.lookups.resolveNext(with: .lookupFailed)
        await waitUntil { harness.clearCount == 1 }

        XCTAssertEqual(
            harness.diagnostics,
            [.lookupFailedClearingLocalSession]
        )
    }

    func testSameIdentityGenerationChangeRejectsStaleLookup() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)

        coordinator.authContextWillChange()
        coordinator.resumeDeferredIfNeeded(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(2)

        await harness.lookups.resolveNext(with: .revoked)
        await harness.lookups.resolveNext(with: .authorized)
        await waitUntil { harness.diagnostics.count == 1 }

        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertEqual(
            harness.diagnostics,
            [.authorizedSessionPreserved]
        )
    }

    func testIdentityChangeRejectsPredecessorAndRevalidatesCurrentUser()
        async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)

        harness.currentIdentity = harness.secondIdentity
        coordinator.authContextWillChange()
        coordinator.resumeDeferredIfNeeded(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(2)

        await harness.lookups.resolveNext(with: .revoked)
        await harness.lookups.resolveNext(with: .authorized)
        await waitUntil { harness.diagnostics.count == 1 }

        let subjects = await harness.lookups.subjects()
        XCTAssertEqual(
            subjects,
            [
                harness.firstIdentity.providerSubject,
                harness.secondIdentity.providerSubject
            ]
        )
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertEqual(
            harness.diagnostics,
            [.authorizedSessionPreserved]
        )
    }

    func testTransitionStartingDuringLookupDefersFreshAttempt() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)

        harness.hasActiveTransition = true
        coordinator.authContextWillChange()
        await harness.lookups.resolveNext(with: .revoked)
        await Task.yield()
        XCTAssertEqual(harness.clearCount, 0)
        let deferredRequestCount = await harness.lookups.requestCount()
        XCTAssertEqual(deferredRequestCount, 1)

        harness.hasActiveTransition = false
        coordinator.resumeDeferredIfNeeded(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(2)
        await harness.lookups.resolveNext(with: .authorized)
        await waitUntil { harness.diagnostics.count == 1 }

        XCTAssertEqual(harness.clearCount, 0)
    }

    func testIdentityChangeAtClearBoundaryRejectsStaleClearAndRevalidates()
        async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity
        harness.beforeClearAdmission = {
            harness.beforeClearAdmission = nil
            harness.currentIdentity = harness.secondIdentity
        }

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        await harness.lookups.resolveNext(with: .revoked)
        await harness.lookups.waitUntilRequestCount(2)
        await harness.lookups.resolveNext(with: .authorized)
        await waitUntil { harness.diagnostics.count == 1 }

        let subjects = await harness.lookups.subjects()
        XCTAssertEqual(
            subjects,
            [
                harness.firstIdentity.providerSubject,
                harness.secondIdentity.providerSubject
            ]
        )
        XCTAssertEqual(harness.clearAdmissionCount, 1)
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertEqual(
            harness.diagnostics,
            [.authorizedSessionPreserved]
        )
    }

    func testTransitionAtClearBoundaryDefersUntilStableRevalidation() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity
        harness.beforeClearAdmission = {
            harness.beforeClearAdmission = nil
            harness.hasActiveTransition = true
        }

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        await harness.lookups.resolveNext(with: .revoked)
        await waitUntil { harness.clearAdmissionCount == 1 }

        let deferredRequestCount = await harness.lookups.requestCount()
        XCTAssertEqual(deferredRequestCount, 1)
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.diagnostics.isEmpty)

        harness.hasActiveTransition = false
        coordinator.resumeDeferredIfNeeded(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(2)
        await harness.lookups.resolveNext(with: .revoked)
        await waitUntil { harness.clearCount == 1 }

        XCTAssertEqual(harness.clearAdmissionCount, 2)
        XCTAssertEqual(
            harness.diagnostics,
            [.unauthorizedCredentialClearingLocalSession]
        )
    }

    func testRecoveryDeferralWaitsForExplicitStableResume() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity
        harness.shouldDeferClear = true

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        await harness.lookups.resolveNext(with: .revoked)
        await waitUntil { harness.clearAdmissionCount == 1 }
        await Task.yield()

        let deferredRequestCount = await harness.lookups.requestCount()
        XCTAssertEqual(deferredRequestCount, 1)
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.diagnostics.isEmpty)

        harness.shouldDeferClear = false
        coordinator.resumeDeferredIfNeeded(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(2)
        await harness.lookups.resolveNext(with: .revoked)
        await waitUntil { harness.clearCount == 1 }

        XCTAssertEqual(harness.clearAdmissionCount, 2)
        XCTAssertEqual(
            harness.diagnostics,
            [.unauthorizedCredentialClearingLocalSession]
        )
    }

    func testContextChangeDuringDeferredClearReplaysWithoutLostWakeup() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity
        harness.shouldDeferClear = true
        harness.beforeClearAdmission = {
            harness.beforeClearAdmission = nil
            coordinator.authContextWillChange()
        }

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        await harness.lookups.resolveNext(with: .revoked)
        await harness.lookups.waitUntilRequestCount(2)

        XCTAssertEqual(harness.clearAdmissionCount, 1)
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.diagnostics.isEmpty)

        harness.shouldDeferClear = false
        await harness.lookups.resolveNext(with: .revoked)
        await waitUntil { harness.clearCount == 1 }

        XCTAssertEqual(harness.clearAdmissionCount, 2)
        XCTAssertEqual(
            harness.diagnostics,
            [.unauthorizedCredentialClearingLocalSession]
        )
    }

    func testOverlappingNotificationsQueueOnlyOneFollowUpLookup() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        let overlappingRequestCount = await harness.lookups.requestCount()
        XCTAssertEqual(overlappingRequestCount, 1)

        await harness.lookups.resolveNext(with: .authorized)
        await harness.lookups.waitUntilRequestCount(2)
        await harness.lookups.resolveNext(with: .authorized)
        await waitUntil { harness.diagnostics.count == 2 }

        let completedRequestCount = await harness.lookups.requestCount()
        XCTAssertEqual(completedRequestCount, 2)
        XCTAssertEqual(harness.clearCount, 0)
    }

    func testCancellationBeforeTaskStartsPerformsNoLookup() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        coordinator.cancel()
        await Task.yield()

        let requestCount = await harness.lookups.requestCount()
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.diagnostics.isEmpty)
    }

    func testCancellationDuringLookupRejectsUnsafeResult() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        coordinator.cancel()
        await harness.lookups.resolveNext(with: .revoked)
        await Task.yield()

        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.diagnostics.isEmpty)
    }

    func testCoordinatorDeinitDoesNotAwaitLookupCompletion() async {
        let harness = AppleRevocationCoordinatorHarness()
        var coordinator: AppleCredentialRevocationCoordinator? =
            AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator?.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        weak let releasedCoordinator = coordinator

        coordinator = nil

        XCTAssertNil(releasedCoordinator)
        await harness.lookups.resolveNext(with: .revoked)
        await Task.yield()
        XCTAssertEqual(harness.clearCount, 0)
        XCTAssertTrue(harness.diagnostics.isEmpty)
    }

    func testUnsafeResultClearsOnceDespiteOverlappingNotification() async {
        let harness = AppleRevocationCoordinatorHarness()
        let coordinator = AppleCredentialRevocationCoordinator()
        harness.currentIdentity = harness.firstIdentity

        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.waitUntilRequestCount(1)
        coordinator.handleRevocationNotification(
            dependencies: harness.dependencies()
        )
        await harness.lookups.resolveNext(with: .revoked)
        await waitUntil { harness.clearCount == 1 }
        await Task.yield()

        let requestCount = await harness.lookups.requestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(harness.clearCount, 1)
        XCTAssertNil(harness.currentIdentity)
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for coordinator state.", file: file, line: line)
    }
}
