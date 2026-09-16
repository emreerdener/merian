import Foundation
@testable import Merian
import Observation
import XCTest

@MainActor
final class AuthRuntimeStateTests: XCTestCase {
    func testTransitionMutationPublishesObservation() async {
        let runtime = AuthRuntimeState()
        let changed = expectation(
            description: "Auth runtime transition state changed"
        )

        withObservationTracking {
            _ = runtime.activeTransition
        } onChange: {
            changed.fulfill()
        }

        let token = runtime.beginTransition(
            kind: .signOut,
            sourceSession: nil
        )

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertNotNil(token)
    }

    func testTransitionOwnsGenerationAnalyticsAndCompletion() {
        let runtime = AuthRuntimeState()
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        let destination = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )

        let token = runtime.beginTransition(
            kind: .oauth(.apple),
            sourceSession: source
        )!
        XCTAssertNil(
            runtime.beginTransition(
                kind: .signOut,
                sourceSession: source
            )
        )
        XCTAssertTrue(runtime.recordAnalyticsGeneration(17, for: token))
        XCTAssertEqual(runtime.analyticsGeneration(for: token), 17)
        XCTAssertTrue(runtime.adoptTransitionSession(destination, for: token))

        XCTAssertEqual(runtime.advanceSessionGeneration(), 1)
        runtime.observeAuthEvent(session: destination)
        XCTAssertTrue(
            runtime.transitionMatchesCurrentSession(
                destination,
                token: token
            )
        )

        let completion = runtime.finishTransition(token)
        XCTAssertEqual(completion?.analyticsGeneration, 17)
        XCTAssertNil(runtime.activeTransition)
        XCTAssertNil(runtime.finishTransition(token))
    }

    func testUnexpectedAuthEventInvalidatesTheTransitionGeneration() {
        let runtime = AuthRuntimeState()
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let token = runtime.beginTransition(
            kind: .signOut,
            sourceSession: source
        )!

        XCTAssertEqual(runtime.advanceSessionGeneration(), 1)
        runtime.observeAuthEvent(
            session: AuthTransitionSession(
                userID: UUID(),
                isAnonymous: true
            )
        )

        XCTAssertFalse(
            runtime.transitionMatchesCurrentSession(source, token: token)
        )
        XCTAssertTrue(runtime.ownsTransition(token))
    }

    func testAccountWorkLeaseRequiresBothExactSessionProjections() {
        let runtime = AuthRuntimeState()
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let lease = runtime.beginAccountWork(
            session: source,
            id: UUID()
        )

        XCTAssertTrue(
            runtime.accountWorkLeaseIsCurrent(
                lease,
                publishedSession: source,
                sdkSession: source
            )
        )
        XCTAssertFalse(
            runtime.accountWorkLeaseIsCurrent(
                lease,
                publishedSession: nil,
                sdkSession: source
            )
        )
        XCTAssertTrue(runtime.finishAccountWork(lease))
        XCTAssertFalse(runtime.finishAccountWork(lease))
    }

    func testAccountWorkDrainWaitsForEveryLease() async {
        let runtime = AuthRuntimeState()
        let probe = AuthRuntimeDrainProbe()
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        let first = runtime.beginAccountWork(session: source, id: UUID())
        let second = runtime.beginAccountWork(session: source, id: UUID())

        let drain = Task { @MainActor in
            await probe.markStarted()
            await runtime.awaitAccountWorkDrain()
            await probe.markFinished()
        }
        await probe.waitUntilStarted()
        await Task.yield()

        XCTAssertTrue(runtime.finishAccountWork(first))
        await Task.yield()
        let finishedAfterFirstLease = await probe.hasFinished()
        XCTAssertFalse(finishedAfterFirstLease)

        XCTAssertTrue(runtime.finishAccountWork(second))
        await drain.value
        let finishedAfterBothLeases = await probe.hasFinished()
        XCTAssertTrue(finishedAfterBothLeases)
    }

    func testSignOutStateInvalidatesTheSessionGeneration() {
        let runtime = AuthRuntimeState()

        runtime.beginSignOut()

        XCTAssertTrue(runtime.isSigningOut)
        XCTAssertEqual(runtime.sessionGeneration, 1)

        runtime.finishSignOut()

        XCTAssertFalse(runtime.isSigningOut)
    }
}

private actor AuthRuntimeDrainProbe {
    private var started = false
    private var finished = false

    func markStarted() {
        started = true
    }

    func markFinished() {
        finished = true
    }

    func hasFinished() -> Bool {
        finished
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }
}
