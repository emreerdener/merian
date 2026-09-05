import Foundation
@testable import Merian
import XCTest

@MainActor
final class AuthTransitionFoundationTests: XCTestCase {
    func testBackgroundAccountWorkQuiescenceFailurePreservesProductLanguage() {
        let message = SupabaseAuthTransitionError
            .accountBoundWorkQuiescenceFailed.errorDescription ?? ""

        XCTAssertTrue(message.contains("account is unchanged"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("ghost"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("guest"))
    }

    func testAuthTransitionCoordinatorSerializesAllSessionMutations() {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        var coordinator = AuthTransitionCoordinator()

        let google = coordinator.begin(
            kind: .oauth(.google),
            sourceSession: source,
            authGeneration: 7,
            id: UUID()
        )
        XCTAssertNotNil(google)
        XCTAssertNil(
            coordinator.begin(
                kind: .signOut,
                sourceSession: source,
                authGeneration: 7
            )
        )
        XCTAssertNil(
            coordinator.begin(
                kind: .oauth(.apple),
                sourceSession: source,
                authGeneration: 7
            )
        )
        XCTAssertNil(
            coordinator.begin(
                kind: .accountDeletion,
                sourceSession: source,
                authGeneration: 7
            )
        )

        XCTAssertTrue(coordinator.finish(google!))
        XCTAssertNotNil(
            coordinator.begin(
                kind: .signOut,
                sourceSession: source,
                authGeneration: 7
            )
        )
    }

    func testDoubleSignOutCallsShareOneTransitionOperationAndResult() async {
        let singleFlight = AuthTransitionSingleFlight()
        let gate = AuthTransitionTestGate()
        let started = expectation(description: "sign-out operation started")
        var operationCount = 0

        let first = Task { @MainActor in
            await singleFlight.run {
                operationCount += 1
                started.fulfill()
                await gate.wait()
                return true
            }
        }
        await fulfillment(of: [started], timeout: 1)
        let second = Task { @MainActor in
            await singleFlight.run {
                operationCount += 1
                return false
            }
        }
        await Task.yield()

        await gate.release()
        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(operationCount, 1)
        XCTAssertFalse(singleFlight.isRunning)
    }

    func testSimultaneousAppleGoogleAndSignOutStartsHaveExactlyOneOwner() async {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        let gate = AuthTransitionTestGate()
        var coordinator = AuthTransitionCoordinator()
        let appleID = UUID()
        let googleID = UUID()
        let signOutID = UUID()

        let apple = Task { @MainActor in
            await gate.wait()
            return coordinator.begin(
                kind: .oauth(.apple),
                sourceSession: source,
                authGeneration: 11,
                id: appleID
            )
        }
        let google = Task { @MainActor in
            await gate.wait()
            return coordinator.begin(
                kind: .oauth(.google),
                sourceSession: source,
                authGeneration: 11,
                id: googleID
            )
        }
        let signOut = Task { @MainActor in
            await gate.wait()
            return coordinator.begin(
                kind: .signOut,
                sourceSession: source,
                authGeneration: 11,
                id: signOutID
            )
        }

        await gate.waitUntilWaiterCount(3)
        await gate.release()
        let appleResult = await apple.value
        let googleResult = await google.value
        let signOutResult = await signOut.value
        let results = [appleResult, googleResult, signOutResult]
        let owners = results.compactMap { $0 }

        XCTAssertEqual(owners.count, 1)
        XCTAssertEqual(coordinator.active?.token, owners[0])
        for candidate in [
            AuthTransitionToken(id: appleID, kind: .oauth(.apple)),
            AuthTransitionToken(id: googleID, kind: .oauth(.google)),
            AuthTransitionToken(id: signOutID, kind: .signOut)
        ] where candidate != owners[0] {
            XCTAssertFalse(coordinator.finish(candidate))
        }
        XCTAssertTrue(coordinator.finish(owners[0]))
    }

    func testAuthTransitionCoordinatorRejectsStaleCallbacksAndSessions() {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        let destination = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        var coordinator = AuthTransitionCoordinator()
        let active = coordinator.begin(
            kind: .oauth(.apple),
            sourceSession: source,
            authGeneration: 3,
            id: UUID()
        )!
        let stale = AuthTransitionToken(
            id: UUID(),
            kind: .oauth(.google)
        )

        coordinator.observeAuthEvent(
            session: destination,
            authGeneration: 4
        )
        XCTAssertTrue(
            coordinator.validatesExpectedSession(
                source,
                authGeneration: 3,
                for: active
            )
        )
        XCTAssertFalse(
            coordinator.adoptExpectedSession(
                destination,
                authGeneration: 4,
                for: stale
            )
        )
        XCTAssertFalse(coordinator.finish(stale))

        XCTAssertTrue(
            coordinator.adoptExpectedSession(
                destination,
                authGeneration: 4,
                for: active
            )
        )
        coordinator.observeAuthEvent(
            session: destination,
            authGeneration: 5
        )
        XCTAssertTrue(
            coordinator.validatesExpectedSession(
                destination,
                authGeneration: 5,
                for: active
            )
        )
        XCTAssertFalse(
            coordinator.validatesExpectedSession(
                source,
                authGeneration: 5,
                for: active
            )
        )
    }

    func testAuthTransitionCoordinatorAdvancesOnlyForExpectedSignedOutEvent() {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        var coordinator = AuthTransitionCoordinator()
        let owner = coordinator.begin(
            kind: .signOut,
            sourceSession: source,
            authGeneration: 3,
            id: UUID()
        )!

        XCTAssertTrue(
            coordinator.adoptExpectedSession(
                nil,
                authGeneration: 4,
                for: owner
            )
        )
        coordinator.observeAuthEvent(
            session: source,
            authGeneration: 5
        )
        XCTAssertTrue(
            coordinator.validatesExpectedSession(
                nil,
                authGeneration: 4,
                for: owner
            )
        )

        coordinator.observeAuthEvent(
            session: nil,
            authGeneration: 6
        )
        XCTAssertTrue(
            coordinator.validatesExpectedSession(
                nil,
                authGeneration: 6,
                for: owner
            )
        )
    }

    func testAccountBoundWorkLeasesRemainSessionBoundUntilEveryLeaseFinishes() {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: false
        )
        var coordinator = AccountBoundWorkCoordinator()
        let first = coordinator.begin(
            session: source,
            id: UUID()
        )
        let second = coordinator.begin(
            session: source,
            id: UUID()
        )

        XCTAssertFalse(coordinator.isEmpty)
        XCTAssertTrue(coordinator.owns(first))
        XCTAssertTrue(coordinator.owns(second))
        XCTAssertTrue(coordinator.finish(first))
        XCTAssertFalse(coordinator.isEmpty)
        XCTAssertFalse(coordinator.owns(first))
        XCTAssertTrue(coordinator.owns(second))
        XCTAssertFalse(
            coordinator.owns(
                AccountBoundWorkLease(
                    id: second.id,
                    session: AuthTransitionSession(
                        userID: UUID(),
                        isAnonymous: true
                    )
                )
            )
        )
        XCTAssertTrue(coordinator.finish(second))
        XCTAssertTrue(coordinator.isEmpty)
        XCTAssertFalse(coordinator.finish(second))
    }

    func testAccountPresentationPolicyShowsOnlyAnonymousUsersAsGuests() {
        let userID = UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!

        XCTAssertTrue(
            AccountPresentationPolicy.isGuest(
                userID: userID,
                authIsAnonymous: true
            )
        )
        XCTAssertFalse(
            AccountPresentationPolicy.isGuest(
                userID: userID,
                authIsAnonymous: false
            )
        )
        XCTAssertTrue(
            AccountPresentationPolicy.isGuest(
                userID: nil,
                authIsAnonymous: false
            ),
            "A missing session must use the anonymous account presentation."
        )
    }
}

private actor AuthTransitionTestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilWaiterCount(_ expectedCount: Int) async {
        while !released && continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func release() {
        released = true
        let pending = continuations
        continuations.removeAll(keepingCapacity: false)
        pending.forEach { $0.resume() }
    }
}
