import Foundation
import Testing
@testable import Merian

@Suite("Purchase Identity Session Coordinator")
@MainActor
struct PurchaseIdentitySessionCoordinatorTests {
    @Test func stableResolutionPublishesOnlyTheExactReadyBinding() async throws {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.binding = try PurchaseIdentitySessionCoordinatorHarness
            .stableBinding()
        let coordinator = PurchaseIdentitySessionCoordinator()

        let identityChanged = await coordinator.ensureIdentity(
            for: harness.snapshot(),
            context: harness.context,
            isAdmissionCurrent: { true },
            dependencies: harness.dependencies()
        )

        #expect(identityChanged)
        #expect(coordinator.activeBinding == harness.binding)
        #expect(coordinator.lastLinkedUserID == harness.userID)
        #expect(harness.publishedHandoffValues == [false])
        #expect(harness.events == [
            "begin-resolution", "resolve", "link-stable"
        ])
    }

    @Test func legacyResolutionUsesTheInjectedProfileLink() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        let coordinator = PurchaseIdentitySessionCoordinator()

        let identityChanged = await coordinator.ensureIdentity(
            for: harness.snapshot(),
            context: harness.context,
            isAdmissionCurrent: { true },
            dependencies: harness.dependencies()
        )

        #expect(identityChanged)
        #expect(coordinator.activeBinding == .legacyFallback)
        #expect(harness.events == [
            "begin-resolution", "resolve", "link-legacy"
        ])
    }

    @Test func pendingHandoffDefersBeforeProviderMutation() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.handoffPending = true
        let coordinator = PurchaseIdentitySessionCoordinator()

        let result = await coordinator.ensureIdentity(
            for: harness.snapshot(),
            context: harness.context,
            isAdmissionCurrent: { true },
            dependencies: harness.dependencies()
        )

        #expect(!result)
        #expect(harness.events == ["defer-handoff"])
        #expect(harness.publishedHandoffValues == [true])
        #expect(harness.resolutionCount == 0)
    }

    @Test func unreadableHandoffStateFailsClosed() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.handoffReadError =
            PurchaseIdentitySessionCoordinatorTestError.failed
        let coordinator = PurchaseIdentitySessionCoordinator()

        let result = await coordinator.ensureIdentity(
            for: harness.snapshot(),
            context: harness.context,
            isAdmissionCurrent: { true },
            dependencies: harness.dependencies()
        )

        #expect(!result)
        #expect(harness.handoffFailures == 1)
        #expect(harness.publishedHandoffValues == [true])
        #expect(harness.resolutionCount == 0)
    }

    @Test func staleGenerationStopsBeforeProviderLink() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.advanceGenerationDuringResolution = true
        let coordinator = PurchaseIdentitySessionCoordinator()

        let result = await coordinator.ensureIdentity(
            for: harness.snapshot(),
            context: harness.context,
            isAdmissionCurrent: { true },
            dependencies: harness.dependencies()
        )

        #expect(!result)
        #expect(coordinator.activeBinding == nil)
        #expect(!harness.events.contains("link-legacy"))
    }

    @Test func readySameIdentitySkipsAnotherResolution() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        let coordinator = PurchaseIdentitySessionCoordinator()
        coordinator.recordBinding(.legacyFallback)
        coordinator.recordLinkedUser(harness.userID)
        harness.providerState = PurchaseIdentityProviderState(
            isIdentityReady: true,
            linkedAuthUserID: harness.userID,
            linkedAccountKind: harness.context.accountKind
        )

        let result = await coordinator.ensureIdentity(
            for: harness.snapshot(),
            context: harness.context,
            isAdmissionCurrent: { true },
            dependencies: harness.dependencies()
        )

        #expect(!result)
        #expect(harness.resolutionCount == 0)
    }

    @Test func staleFinalAdmissionDoesNotRecordTheLinkedUser() async {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        let coordinator = PurchaseIdentitySessionCoordinator()
        var admissionChecks = 0

        let result = await coordinator.ensureIdentity(
            for: harness.snapshot(),
            context: harness.context,
            isAdmissionCurrent: {
                admissionChecks += 1
                return admissionChecks == 1
            },
            dependencies: harness.dependencies()
        )

        #expect(!result)
        #expect(coordinator.activeBinding == .legacyFallback)
        #expect(coordinator.lastLinkedUserID == nil)
        #expect(admissionChecks == 2)
    }

    @Test func sameContextSharesOneResolutionTask() async throws {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.suspendResolution = true
        let coordinator = PurchaseIdentitySessionCoordinator()
        let context = harness.context
        let dependencies = harness.dependencies()

        let first = Task { @MainActor in
            await coordinator.ensureIdentity(
                for: harness.snapshot(),
                context: context,
                isAdmissionCurrent: { true },
                dependencies: dependencies
            )
        }
        defer { harness.resumeAllResolutions() }
        for _ in 0..<20 where harness.resolutionContinuations.isEmpty {
            await Task.yield()
        }
        try #require(harness.resolutionContinuations.count == 1)

        let second = Task { @MainActor in
            await coordinator.ensureIdentity(
                for: harness.snapshot(),
                context: context,
                isAdmissionCurrent: { true },
                dependencies: dependencies
            )
        }
        await Task.yield()
        #expect(harness.resolutionCount == 1)
        harness.resumeResolution()

        #expect(await first.value)
        #expect(await second.value)
        #expect(harness.resolutionCount == 1)
    }

    @Test func supersededResolutionCannotPublishOverTheNewerTask()
        async throws {
        let harness = PurchaseIdentitySessionCoordinatorHarness()
        harness.suspendResolution = true
        let coordinator = PurchaseIdentitySessionCoordinator()
        let context = harness.context
        let dependencies = harness.dependencies()
        let newerBinding = try PurchaseIdentitySessionCoordinatorHarness
            .stableBinding()

        let first = Task { @MainActor in
            await coordinator.ensureIdentity(
                for: harness.snapshot(),
                context: context,
                expectedCapabilityFingerprint: String(
                    repeating: "a",
                    count: 64
                ),
                isAdmissionCurrent: { true },
                dependencies: dependencies
            )
        }
        defer { harness.resumeAllResolutions() }
        for _ in 0..<20 where harness.resolutionContinuations.count < 1 {
            await Task.yield()
        }
        try #require(harness.resolutionContinuations.count == 1)

        let second = Task { @MainActor in
            await coordinator.ensureIdentity(
                for: harness.snapshot(),
                context: context,
                expectedCapabilityFingerprint: String(
                    repeating: "b",
                    count: 64
                ),
                isAdmissionCurrent: { true },
                dependencies: dependencies
            )
        }
        for _ in 0..<20 where harness.resolutionContinuations.count < 2 {
            await Task.yield()
        }
        try #require(harness.resolutionContinuations.count == 2)

        harness.resumeResolution(at: 1, returning: newerBinding)
        #expect(await second.value)
        #expect(coordinator.activeBinding == newerBinding)

        harness.resumeResolution(returning: .legacyFallback)
        #expect(!(await first.value))
        #expect(coordinator.activeBinding == newerBinding)
        #expect(coordinator.lastLinkedUserID == harness.userID)
        #expect(harness.resolutionCount == 2)
    }
}
