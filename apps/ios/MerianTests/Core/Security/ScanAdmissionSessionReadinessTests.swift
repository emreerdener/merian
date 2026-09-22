@testable import Merian
import XCTest

@MainActor
final class ScanAdmissionSessionReadinessTests: XCTestCase {
    func testPhotoPickerAdmissionWaitsThenAllowsPresentationWithoutError() async {
        let harness = Harness()
        let gate = Gate()
        harness.gate = gate
        harness.transition = .anonymousBootstrap
        let viewModel = makeViewModel(harness: harness)
        let attempt = Task { await viewModel.requestImageImportEntryAdmission(prospectiveImageCount: 1) }
        await gate.waitUntilStarted()

        XCTAssertTrue(viewModel.isCheckingScanAdmission)
        XCTAssertNil(viewModel.offlineToastMessage)
        XCTAssertEqual(harness.previewCount, 0)
        harness.publish(harness.identity)
        gate.release()

        let shouldPresentPicker = await attempt.value

        XCTAssertTrue(shouldPresentPicker)
        XCTAssertFalse(viewModel.isCheckingScanAdmission)
        XCTAssertNil(viewModel.offlineToastMessage)
        XCTAssertEqual(harness.previewCount, 1)
        XCTAssertTrue(viewModel.stagedCapture.isEmpty)
    }

    func testCancelledPhotoPickerAdmissionClearsBusyStateWithoutLatePresentation() async {
        let harness = Harness()
        let gate = Gate()
        harness.gate = gate
        let viewModel = makeViewModel(harness: harness)
        let attempt = Task { await viewModel.requestImageImportEntryAdmission(prospectiveImageCount: 1) }
        await gate.waitUntilStarted()
        attempt.cancel()

        let shouldPresentPicker = await attempt.value

        XCTAssertFalse(shouldPresentPicker)
        XCTAssertFalse(viewModel.isCheckingScanAdmission)
        XCTAssertNil(viewModel.offlineToastMessage)
        XCTAssertEqual(harness.previewCount, 0)
        harness.publish(harness.identity)
        gate.release()
    }

    func testFirstImportWaitsForWarmupToPublishSession() async {
        let harness = Harness()
        harness.transition = .anonymousBootstrap
        let gate = Gate()
        harness.gate = gate
        let attempt = Task { await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies) }
        await gate.waitUntilStarted()

        // The old immediate account-lease guard rejects precisely this state.
        XCTAssertFalse(harness.snapshot.isReady)
        XCTAssertEqual(harness.initializeCount, 1)
        harness.publish(harness.identity)
        gate.release()

        let ready = await attempt.value
        XCTAssertTrue(ready)
    }

    func testFailedFirstBootstrapCanBeRetriedByNextImport() async {
        let harness = Harness()
        harness.result = nil
        let first = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)
        XCTAssertFalse(first)
        harness.result = harness.identity
        harness.publishOnInitialize = true

        let retry = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)

        XCTAssertTrue(retry)
        XCTAssertEqual(harness.initializeCount, 2)
    }

    func testExistingReadySessionSkipsBootstrapEvenForPreviousOAuthUser() async {
        let harness = Harness()
        harness.publish(harness.identity)
        harness.bootstrapBlocked = true

        let ready = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)

        XCTAssertTrue(ready)
        XCTAssertEqual(harness.initializeCount, 0)
    }

    func testMissingSessionDoesNotBootstrapWhenIdentityRecoveryIsBlocked() async {
        let harness = Harness()
        harness.bootstrapBlocked = true

        let ready = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)

        XCTAssertFalse(ready)
        XCTAssertEqual(harness.initializeCount, 0)
    }

    func testUnpublishedOAuthIdentityRequiresExistingRecoveryRatherThanAnonymousSetup() async {
        let harness = Harness()
        harness.sdkSession = AuthTransitionSession(userID: UUID(), isAnonymous: false)
        harness.bootstrapBlocked = true
        let ready = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)
        XCTAssertFalse(ready)
        XCTAssertEqual(harness.initializeCount, 0)
    }

    func testOtherAuthTransitionsDoNotStartBootstrap() async {
        for transition in [
            AuthTransitionKind.signOut, .oauth(.apple), .oauth(.google),
            .authenticationCallback, .recovery, .accountDeletion, .accountDeletionCleanup
        ] {
            let harness = Harness()
            harness.transition = transition
            let ready = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)
            XCTAssertFalse(ready)
            XCTAssertEqual(harness.initializeCount, 0)
        }
    }

    func testUnpublishedSDKSessionWaitsForPublication() async {
        let harness = Harness()
        harness.sdkSession = harness.identity
        harness.publishOnInitialize = true

        let ready = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)

        XCTAssertTrue(ready)
        XCTAssertEqual(harness.initializeCount, 1)
    }

    func testCancellationWhileWaitingCannotAdmitImport() async {
        let harness = Harness()
        let gate = Gate()
        harness.gate = gate
        let attempt = Task { await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies) }
        await gate.waitUntilStarted()
        attempt.cancel()
        let ready = await attempt.value
        XCTAssertFalse(ready)

        // A non-cooperative shared bootstrap may finish later; it cannot keep
        // the cancelled import suspended or change the already-returned result.
        harness.publish(harness.identity)
        gate.release()
    }

    func testDeadlineReturnsBeforeNonCooperativeBootstrapFinishes() async {
        let harness = Harness()
        let bootstrap = Gate()
        let deadline = Gate()
        harness.gate = bootstrap
        var dependencies = harness.dependencies
        dependencies.waitForDeadline = { await deadline.wait() }
        let configuredDependencies = dependencies
        let attempt = Task { await ScanAdmissionSessionReadiness.prepare(using: configuredDependencies) }
        await bootstrap.waitUntilStarted()
        await deadline.waitUntilStarted()
        deadline.release()

        let ready = await attempt.value

        XCTAssertFalse(ready)
        XCTAssertEqual(ScanAdmissionSessionReadiness.preparationTimeout, .seconds(5))
        harness.publish(harness.identity)
        bootstrap.release()
    }

    func testChangedAccountCannotAdmitOldImport() async {
        let harness = Harness()
        harness.sdkSession = harness.identity
        let gate = Gate()
        harness.gate = gate
        let attempt = Task { await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies) }
        await gate.waitUntilStarted()
        let replacement = AuthTransitionSession(userID: UUID(), isAnonymous: false)
        harness.result = replacement
        harness.publish(replacement)
        gate.release()

        let ready = await attempt.value

        XCTAssertFalse(ready)
    }

    func testDeadlineDependencyFailureDoesNotLeaveCallerWaiting() async {
        let harness = Harness()
        let bootstrap = Gate()
        harness.gate = bootstrap
        var dependencies = harness.dependencies
        dependencies.waitForDeadline = {
            await bootstrap.waitUntilStarted()
            throw URLError(.unknown)
        }

        let ready = await ScanAdmissionSessionReadiness.prepare(using: dependencies)

        XCTAssertFalse(ready)
        bootstrap.release()
    }

    func testUnfinishedTransitionStillBlocksAfterSessionPublication() async {
        let harness = Harness()
        harness.publish(harness.identity)
        harness.transition = .anonymousBootstrap

        let ready = await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies)

        XCTAssertFalse(ready)
    }
}

private extension ScanAdmissionSessionReadinessTests {
    func makeViewModel(harness: Harness) -> CaptureWorkspaceViewModel {
        let container = AppDIContainer.preview
        let base = CaptureWorkspaceDependencies.live(diContainer: container)
        let submission = CaptureSubmissionDependencies(
            context: base.submission.context,
            admission: .init(isOnline: { true }, canStartLocally: { _ in true }, preview: { _ in
                guard await ScanAdmissionSessionReadiness.prepare(using: harness.dependencies) else {
                    return .unavailable
                }
                harness.previewCount += 1
                return .available(.init(
                    decision: .allowed, effectivePlan: "free", dailyLimit: nil, dailyRemaining: nil
                ))
            }),
            deferredContext: base.submission.deferredContext
        )
        let dependencies = CaptureWorkspaceDependencies(
            scan: base.scan,
            submission: submission,
            controls: base.controls,
            navigation: base.navigation,
            stagingToolbar: base.stagingToolbar,
            prepareImage: base.prepareImage,
            prepareHistoricalAudio: base.prepareHistoricalAudio,
            externalImageImports: base.externalImageImports,
            downloadRefinementImage: base.downloadRefinementImage,
            prewarmConnections: {},
            sharedExplorePostId: base.sharedExplorePostId,
            captureGoalAccountId: base.captureGoalAccountId,
            requestNotificationAuthorization: base.requestNotificationAuthorization,
            feedback: base.feedback
        )
        return CaptureWorkspaceViewModel(
            diContainer: container, dependencies: dependencies, prewarmHeadersOnInit: false
        )
    }

    @MainActor
    final class Harness {
        let identity = AuthTransitionSession(userID: UUID(), isAnonymous: true)
        var publishedSession: AuthTransitionSession?
        var sdkSession: AuthTransitionSession?
        var allowsAccountWork = false
        var transition: AuthTransitionKind?
        var bootstrapBlocked = false
        var initializeCount = 0
        var previewCount = 0
        var gate: Gate?
        var publishOnInitialize = false
        var result: AuthTransitionSession?

        init() { result = identity }

        var snapshot: ScanAdmissionSessionReadiness.Snapshot {
            .init(
                publishedSession: publishedSession,
                sdkSession: sdkSession,
                allowsAccountWork: allowsAccountWork,
                transition: transition,
                bootstrapBlocked: bootstrapBlocked
            )
        }

        var dependencies: ScanAdmissionSessionReadiness.Dependencies {
            .init(snapshot: { self.snapshot }, initialize: {
                self.initializeCount += 1
                if let gate = self.gate { await gate.wait() }
                if self.publishOnInitialize, let result = self.result { self.publish(result) }
                return self.result
            })
        }

        func publish(_ identity: AuthTransitionSession) {
            publishedSession = identity
            sdkSession = identity
            allowsAccountWork = true
            transition = nil
        }
    }

    @MainActor
    final class Gate {
        private var waiter: CheckedContinuation<Void, Never>?
        private var observer: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation in
                waiter = continuation
                observer?.resume()
                observer = nil
            }
        }

        func waitUntilStarted() async {
            if waiter != nil { return }
            await withCheckedContinuation { observer = $0 }
        }

        func release() {
            waiter?.resume()
            waiter = nil
        }
    }
}
