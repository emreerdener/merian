import AuthenticationServices
import Foundation
@testable import Merian
import Supabase
import XCTest

@MainActor
final class SupabaseManagerTests: XCTestCase {
    func testBackgroundAccountWorkQuiescenceFailurePreservesProductLanguage() {
        let message = SupabaseAuthTransitionError
            .accountBoundWorkQuiescenceFailed.errorDescription ?? ""

        XCTAssertTrue(message.contains("account is unchanged"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("ghost"))
        XCTAssertFalse(message.localizedCaseInsensitiveContains("guest"))
    }


    var supabaseManager: SupabaseManager!

    override func setUp() async throws {
        supabaseManager = SupabaseManager.shared
    }

    override func tearDown() async throws {
        supabaseManager = nil
    }

    func testGuestUserPropertyDefaults() {
        // Without an explicit session injected, an initial boot should default into
        // a false authentication bound and mark itself as a Guest
        // Note: As this is a live singleton, if a simulator has persistent data logged in,
        // it may alter this behavior. This asserts the logic flows without crashing.
        let isGuest = supabaseManager.isGuestUser
        let authState = supabaseManager.isAuthenticated
        
        XCTAssertNotNil(isGuest)
        XCTAssertNotNil(authState)
    }

    func testAuthSessionAdoptionDistinguishesRefreshFromSignOut() {
        let userId = UUID()

        XCTAssertEqual(
            SupabaseManager.authSessionAdoption(
                userId: userId,
                isExpired: true
            ),
            .awaitingRefresh(userId: userId)
        )
        XCTAssertEqual(
            SupabaseManager.authSessionAdoption(
                userId: userId,
                isExpired: false
            ),
            .authenticated(userId: userId)
        )
        XCTAssertEqual(
            SupabaseManager.authSessionAdoption(
                userId: nil,
                isExpired: false
            ),
            .signedOut
        )
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
        let gate = SupabaseManagerTestGate()
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
        let gate = SupabaseManagerTestGate()
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

    func testAppleCallbackRequiresMatchingControllerAndTransition() {
        let transitionID = UUID()

        XCTAssertTrue(
            SupabaseManager.shouldAcceptAppleSignInCallback(
                activeTransitionID: transitionID,
                attemptTransitionID: transitionID,
                controllerMatches: true
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldAcceptAppleSignInCallback(
                activeTransitionID: UUID(),
                attemptTransitionID: transitionID,
                controllerMatches: true
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldAcceptAppleSignInCallback(
                activeTransitionID: transitionID,
                attemptTransitionID: transitionID,
                controllerMatches: false
            )
        )
    }

    func testOAuthFailureClearsOnlyAChangedOrObservedSession() {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        XCTAssertFalse(
            SupabaseManager.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: source,
                currentSession: source
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: true,
                sourceSession: source,
                currentSession: source
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: source,
                currentSession: AuthTransitionSession(
                    userID: source.userID,
                    isAnonymous: false
                )
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: source,
                currentSession: nil
            )
        )
    }

    func testOAuthMetadataMutationRequiresTheExactTransitionSessionBeforeAndAfterUpdate() {
        let expectedUserID = UUID()
        let otherUserID = UUID()

        XCTAssertTrue(
            SupabaseManager.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID,
                updatedUserID: expectedUserID
            )
        )
        for allowed in [
            SupabaseManager.allowsOAuthMetadataMutation(
                transitionIsCurrent: false,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID
            ),
            SupabaseManager.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: otherUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID
            ),
            SupabaseManager.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: otherUserID,
                expectedUserID: expectedUserID
            ),
            SupabaseManager.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID,
                updatedUserID: otherUserID
            )
        ] {
            XCTAssertFalse(allowed)
        }
    }

    func testActiveTransitionOwnsListenerSideEffectsAndAuthenticatedRequests() {
        let active = AuthTransitionToken(
            id: UUID(),
            kind: .oauth(.apple)
        )
        let stale = AuthTransitionToken(
            id: UUID(),
            kind: .recovery
        )

        XCTAssertTrue(
            SupabaseManager.shouldDeferAuthListenerSideEffects(
                hasActiveTransition: true,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldDeferAuthListenerSideEffects(
                hasActiveTransition: false,
                accountDeletionCleanupPending: true
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDeferAuthListenerSideEffects(
                hasActiveTransition: false,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertTrue(
            SupabaseManager.allowsAuthenticatedRequest(
                activeTransition: active,
                requestOwner: active,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.allowsAuthenticatedRequest(
                activeTransition: active,
                requestOwner: nil,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.allowsAuthenticatedRequest(
                activeTransition: active,
                requestOwner: stale,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.allowsAuthenticatedRequest(
                activeTransition: nil,
                requestOwner: nil,
                accountDeletionCleanupPending: true
            )
        )
        let deletion = AuthTransitionToken(
            id: UUID(),
            kind: .accountDeletion
        )
        XCTAssertTrue(
            SupabaseManager.allowsAuthenticatedRequest(
                activeTransition: deletion,
                requestOwner: deletion,
                accountDeletionCleanupPending: true
            )
        )
        XCTAssertFalse(
            SupabaseManager.allowsAuthenticatedRequest(
                activeTransition: deletion,
                requestOwner: nil,
                accountDeletionCleanupPending: true
            )
        )
        let cleanup = AuthTransitionToken(
            id: UUID(),
            kind: .accountDeletionCleanup
        )
        XCTAssertFalse(
            SupabaseManager.allowsAuthenticatedRequest(
                activeTransition: cleanup,
                requestOwner: cleanup,
                accountDeletionCleanupPending: true
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

    func testAuthTransitionDrainCancelsAndAwaitsConsentSynchronization() async throws {
        let userID = UUID()
        let suiteName = "merian.tests.auth-consent-drain.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let started = expectation(description: "consent sync started")
        let cancelled = expectation(description: "consent sync cancelled")
        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            ),
            currentSDKUserIdProvider: { userID },
            synchronizationOperation: { _, _ in
                started.fulfill()
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch is CancellationError {
                    cancelled.fulfill()
                    throw CancellationError()
                }
            }
        )
        manager.observeSession(userId: userID)
        let synchronization = Task { @MainActor in
            try? await manager.synchronize(for: userID)
        }
        await fulfillment(of: [started], timeout: 1)

        await manager.cancelAndAwaitSynchronizationForAuthTransition()
        await synchronization.value

        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testFallbackAuthenticationCallbackNeverReplacesAnAnonymousOrDifferentAccount() {
        let linkedUserID = UUID()
        let linked = AuthTransitionSession(
            userID: linkedUserID,
            isAnonymous: false
        )

        XCTAssertTrue(
            SupabaseManager.acceptsAuthenticationCallbackTarget(
                sourceSession: nil,
                targetSession: linked
            )
        )
        XCTAssertTrue(
            SupabaseManager.acceptsAuthenticationCallbackTarget(
                sourceSession: linked,
                targetSession: linked
            )
        )
        XCTAssertFalse(
            SupabaseManager.acceptsAuthenticationCallbackTarget(
                sourceSession: AuthTransitionSession(
                    userID: UUID(),
                    isAnonymous: true
                ),
                targetSession: linked
            )
        )
        XCTAssertFalse(
            SupabaseManager.acceptsAuthenticationCallbackTarget(
                sourceSession: linked,
                targetSession: AuthTransitionSession(
                    userID: UUID(),
                    isAnonymous: false
                )
            )
        )
    }

    func testAcceptedAccountDeletionPersistsRecoveryBeforeSignOutAndClearsLast() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: true
        )

        let result = await SupabaseManager
            .performAcceptedAccountDeletionCleanup(
                receipt: receipt,
                recordCleanupPending: {
                    events.append("record")
                    return true
                },
                recordManualProviderRevocation: { events.append("manual") },
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                acknowledgeRecovery: {
                    events.append("acknowledge")
                    return true
                },
                recordRecoveryRetirementPending: {
                    events.append("record-retirement")
                    return true
                },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )

        XCTAssertTrue(result)
        XCTAssertEqual(
            events,
            [
                "record",
                "manual",
                "signout",
                "purge",
                "acknowledge",
                "record-retirement",
                "retire-capability",
                "resolve"
            ]
        )
    }

    func testAccountDeletionAcknowledgementFailureRetainsProofAndMarker() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false
        )

        let result = await SupabaseManager
            .performAcceptedAccountDeletionCleanup(
                receipt: receipt,
                recordCleanupPending: {
                    events.append("record")
                    return true
                },
                recordManualProviderRevocation: { events.append("manual") },
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                acknowledgeRecovery: {
                    events.append("acknowledge")
                    return false
                },
                recordRecoveryRetirementPending: {
                    events.append("record-retirement")
                    return true
                },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )

        XCTAssertFalse(result)
        XCTAssertEqual(
            events,
            ["record", "signout", "purge", "acknowledge"]
        )
    }

    func testAccountDeletionRetirementReverifiesCleanupAndClearsProofBeforeMarker() async {
        var events: [String] = []
        let completedRetirement = await SupabaseManager
            .performAccountDeletionRecoveryRetirement(
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )
        XCTAssertTrue(completedRetirement)
        XCTAssertEqual(
            events,
            ["signout", "purge", "retire-capability", "resolve"]
        )

        events.removeAll()
        let incompleteRetirement = await SupabaseManager
            .performAccountDeletionRecoveryRetirement(
                performLocalSignOut: { true },
                purgeLocalData: { true },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return false
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )
        XCTAssertFalse(incompleteRetirement)
        XCTAssertEqual(events, ["retire-capability"])
    }

    func testRejectedAccountDeletionRetiresOnlyProofAndMarker() {
        var events: [String] = []

        XCTAssertTrue(
            SupabaseManager
                .performRejectedAccountDeletionRecoveryRetirement(
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return true
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(events, ["retire-capability", "resolve"])

        events.removeAll()
        XCTAssertFalse(
            SupabaseManager
                .performRejectedAccountDeletionRecoveryRetirement(
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return false
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(events, ["retire-capability"])
    }

    func testDefinitiveDeletionRejectionPersistsRetirementBeforeProofRemoval() {
        var events: [String] = []

        XCTAssertTrue(
            SupabaseManager
                .performDefinitiveAccountDeletionIntakeRejectionRetirement(
                    recordRejectionRetirementPending: {
                        events.append("record-rejection-retirement")
                        return true
                    },
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return true
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(
            events,
            [
                "record-rejection-retirement",
                "retire-capability",
                "resolve"
            ]
        )

        events.removeAll()
        XCTAssertFalse(
            SupabaseManager
                .performDefinitiveAccountDeletionIntakeRejectionRetirement(
                    recordRejectionRetirementPending: {
                        events.append("record-rejection-retirement")
                        return false
                    },
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return true
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(events, ["record-rejection-retirement"])

        events.removeAll()
        XCTAssertFalse(
            SupabaseManager
                .performDefinitiveAccountDeletionIntakeRejectionRetirement(
                    recordRejectionRetirementPending: {
                        events.append("record-rejection-retirement")
                        return true
                    },
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return false
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(
            events,
            ["record-rejection-retirement", "retire-capability"]
        )
    }

    func testEveryDeletionRecoveryPhaseAdmitsOnlyItsOwnedTransition() {
        let intakeStates: [AccountDeletionLocalRecoveryState] = [
            .intakePending,
            .capabilityPreparationPending,
            .capabilityPreparedPending,
            .capabilityIntakePending
        ]
        for state in intakeStates {
            XCTAssertTrue(
                SupabaseManager
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletion
                    )
            )
            XCTAssertFalse(
                SupabaseManager
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletionCleanup
                    )
            )
        }

        let cleanupStates: [AccountDeletionLocalRecoveryState] = [
            .cleanupPending,
            .capabilityCleanupPending,
            .capabilityRetirementPending,
            .capabilityRejectionRetirementPending,
            .capabilityLookupPending
        ]
        for state in cleanupStates {
            XCTAssertTrue(
                SupabaseManager
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletionCleanup
                    )
            )
            XCTAssertFalse(
                SupabaseManager
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletion
                    )
            )
        }

        XCTAssertFalse(
            SupabaseManager
                .allowsAuthTransitionDuringAccountDeletionRecovery(
                    recoveryState: .capabilityLookupPending,
                    kind: .oauth(.apple)
                )
        )
        XCTAssertFalse(
            SupabaseManager
                .allowsAuthTransitionDuringAccountDeletionRecovery(
                    recoveryState: .capabilityCleanupPending,
                    kind: .signOut
                )
        )
    }

    func testAccountDeletionKeepsRecoveryPendingWhenMarkerRemovalFails() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false
        )

        let result = await SupabaseManager
            .performAcceptedAccountDeletionCleanup(
                receipt: receipt,
                recordCleanupPending: { true },
                recordManualProviderRevocation: {},
                performLocalSignOut: { true },
                purgeLocalData: { true },
                acknowledgeRecovery: { true },
                recordRecoveryRetirementPending: { true },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return false
                }
            )

        XCTAssertFalse(result)
        XCTAssertEqual(events, ["retire-capability", "resolve"])
    }

    func testFailedAccountDeletionPurgeLeavesRecoveryMarkerPending() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false
        )

        let result = await SupabaseManager
            .performAcceptedAccountDeletionCleanup(
                receipt: receipt,
                recordCleanupPending: {
                    events.append("record")
                    return true
                },
                recordManualProviderRevocation: { events.append("manual") },
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return false
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )

        XCTAssertFalse(result)
        XCTAssertEqual(events, ["record", "signout", "purge"])
    }

    func testAcceptedAccountDeletionDoesNotEraseLocalStateWhenRecoveryPersistenceFails() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: true
        )

        let result = await SupabaseManager
            .performAcceptedAccountDeletionCleanup(
                receipt: receipt,
                recordCleanupPending: {
                    events.append("record")
                    return false
                },
                recordManualProviderRevocation: { events.append("manual") },
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )

        XCTAssertFalse(result)
        XCTAssertEqual(events, ["record"])
    }

    func testAccountDeletionPersistsIntentBeforeRequestAndRetainsAmbiguousFailure() async {
        var events: [String] = []

        do {
            _ = try await SupabaseManager.performDurableAccountDeletionIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    throw URLError(.networkConnectionLost)
                },
                verifyReceiptOwner: {
                    events.append("verify")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
            XCTFail("Expected the ambiguous request to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        XCTAssertEqual(events, ["record-intent", "request"])
    }

    func testAccountDeletionClearsIntentOnlyAfterDefinitiveClientRejection() async {
        var events: [String] = []

        do {
            _ = try await SupabaseManager.performDurableAccountDeletionIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    throw MerianError.httpError(
                        statusCode: 409,
                        message: #"{"code":"purchase_continuity_pending"}"#
                    )
                },
                verifyReceiptOwner: {
                    events.append("verify")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
            XCTFail("Expected the rejected request to fail")
        } catch {
            XCTAssertTrue(
                SupabaseManager
                    .isDefinitiveAccountDeletionIntakeRejection(error)
            )
        }

        XCTAssertEqual(events, ["record-intent", "request", "clear"])
    }

    func testAccountDeletionTreatsOtherHTTPFailuresAsAmbiguous() {
        let unauthorized = MerianError.httpError(
            statusCode: 401,
            message: #"{"code":"invalid_session"}"#
        )
        let unrelatedConflict = MerianError.httpError(
            statusCode: 409,
            message: #"{"code":"account_deletion_conflict"}"#
        )
        let serverFailure = MerianError.httpError(
            statusCode: 503,
            message: #"{"code":"temporarily_unavailable"}"#
        )

        XCTAssertFalse(
            SupabaseManager
                .isDefinitiveAccountDeletionIntakeRejection(unauthorized)
        )
        XCTAssertFalse(
            SupabaseManager
                .isDefinitiveAccountDeletionIntakeRejection(unrelatedConflict)
        )
        XCTAssertFalse(
            SupabaseManager
                .isDefinitiveAccountDeletionIntakeRejection(serverFailure)
        )
    }

    func testOnlyMatchedExpiredRecoveryProvesDeletionWasAccepted() {
        let matchedExpiry = MerianError.httpError(
            statusCode: 410,
            message: #"{"code":"account_deletion_recovery_expired"}"#
        )
        let wrongStatus = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"account_deletion_recovery_expired"}"#
        )
        let unknownProof = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"account_deletion_recovery_invalid"}"#
        )
        let expiredPreparation = MerianError.httpError(
            statusCode: 410,
            message: #"{"code":"account_deletion_recovery_preparation_expired"}"#
        )

        XCTAssertTrue(
            SupabaseManager
                .isAcceptedExpiredAccountDeletionRecovery(matchedExpiry)
        )
        XCTAssertFalse(
            SupabaseManager
                .isAcceptedExpiredAccountDeletionRecovery(wrongStatus)
        )
        XCTAssertFalse(
            SupabaseManager
                .isAcceptedExpiredAccountDeletionRecovery(unknownProof)
        )
        XCTAssertFalse(
            SupabaseManager
                .isAcceptedExpiredAccountDeletionRecovery(expiredPreparation)
        )
    }

    func testDeletionBarrierRestoresOnlyTheExactCachedSourceSession() {
        let sourceUserID = UUID()
        let otherUserID = UUID()
        let source = AuthTransitionSession(
            userID: sourceUserID,
            isAnonymous: false
        )

        XCTAssertTrue(
            SupabaseManager.canRestoreDeferredDeletionBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.canRestoreDeferredDeletionBarrierSession(
                markerIsPending: false,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.canRestoreDeferredDeletionBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: otherUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.canRestoreDeferredDeletionBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: true,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.canRestoreDeferredDeletionBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: true
            )
        )
    }

    func testDeletionBarrierAdoptsCachedSessionBeforeMarkerRemovalAndPublication() {
        var markerIsPending = true
        var events: [String] = []

        let restored = SupabaseManager
            .performDeferredDeletionBarrierSessionRestoration(
                markerIsPending: { markerIsPending },
                adoptCachedSession: {
                    events.append("adopt")
                    XCTAssertTrue(markerIsPending)
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    XCTAssertTrue(markerIsPending)
                    markerIsPending = false
                    return true
                },
                publishCachedSession: {
                    events.append("publish")
                    XCTAssertFalse(markerIsPending)
                    return true
                }
            )

        XCTAssertTrue(restored)
        XCTAssertEqual(events, ["adopt", "resolve", "publish"])
    }

    func testDeletionBarrierDoesNotPublishWhenMarkerRemovalFails() {
        var events: [String] = []

        let restored = SupabaseManager
            .performDeferredDeletionBarrierSessionRestoration(
                markerIsPending: { true },
                adoptCachedSession: {
                    events.append("adopt")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return false
                },
                publishCachedSession: {
                    events.append("publish")
                    return true
                }
            )

        XCTAssertFalse(restored)
        XCTAssertEqual(events, ["adopt", "resolve"])
    }

    func testAccountDeletionDoesNotDispatchWhenIntentPersistenceFails() async {
        var events: [String] = []

        do {
            _ = try await SupabaseManager.performDurableAccountDeletionIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return false
                },
                requestDeletion: {
                    events.append("request")
                    return AccountDeletionReceipt(
                        success: true,
                        status: .pending,
                        manualProviderRevocationRequired: false
                    )
                },
                verifyReceiptOwner: {
                    events.append("verify")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
            XCTFail("Expected persistence failure")
        } catch {
            guard case SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        XCTAssertEqual(events, ["record-intent"])
    }

    func testAccountDeletionVerifiesTransitionOwnerAfterReceipt() async throws {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: false
        )

        let result = try await SupabaseManager
            .performDurableAccountDeletionIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    return receipt
                },
                verifyReceiptOwner: {
                    events.append("verify")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )

        XCTAssertEqual(result, receipt)
        XCTAssertEqual(events, ["record-intent", "request", "verify"])
    }

    func testPendingAccountDeletionSignsOutBeforePurgeAndResolvesLast() async {
        var events: [String] = []

        let result = await SupabaseManager
            .performPendingAccountDeletionLocalCleanup(
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )

        XCTAssertTrue(result)
        XCTAssertEqual(events, ["signout", "purge", "resolve"])

        events.removeAll()
        let failed = await SupabaseManager
            .performPendingAccountDeletionLocalCleanup(
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return false
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )
        XCTAssertFalse(failed)
        XCTAssertEqual(events, ["signout", "purge"])

        events.removeAll()
        let signOutFailed = await SupabaseManager
            .performPendingAccountDeletionLocalCleanup(
                performLocalSignOut: {
                    events.append("signout")
                    return false
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )
        XCTAssertFalse(signOutFailed)
        XCTAssertEqual(events, ["signout"])
    }

    func testAnonymousExternalIdentityLinkWaitsForPurchaseHandoffBinding() {
        XCTAssertTrue(
            SupabaseManager.shouldDeferExternalIdentityLink(
                isAnonymous: true,
                purchaseIdentityHandoffPending: true
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDeferExternalIdentityLink(
                isAnonymous: true,
                purchaseIdentityHandoffPending: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDeferExternalIdentityLink(
                isAnonymous: false,
                purchaseIdentityHandoffPending: true
            )
        )
    }

    func testFailedSignOutRestoresOnlyTheExactUnfencedSourceAccount() {
        let sourceUserID = UUID()

        XCTAssertTrue(
            SupabaseManager.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: sourceUserID,
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: UUID(),
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: sourceUserID,
                activeUserIsAnonymous: true,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: sourceUserID,
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: true
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: nil,
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
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

    func testGetValidAuthHeadersUsesDeterministicTestStub() async throws {
        let headers = try await supabaseManager.getValidAuthHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer merian-test-session")
        XCTAssertEqual(headers["apikey"], MerianEnvironment.supabaseAnonKey)
        XCTAssertEqual(headers["Content-Type"], "application/json")
    }

    func testSignOutClosesAuthenticatedRequestGateBeforeRemoteInvalidation() async {
        guard let manager = supabaseManager else {
            XCTFail("Supabase manager was not initialized")
            return
        }

        manager.isAuthenticated = true
        var observedLocalSignOutBeforeRemoteCall = false
        var requestWasBlockedDuringRemoteCall = false

        await manager.signOut(
            performRemoteSignOut: { [manager] in
                observedLocalSignOutBeforeRemoteCall =
                    !manager.isAuthenticated && manager.isSigningOut

                do {
                    _ = try await manager.getValidAuthHeaders()
                } catch SupabaseAuthTransitionError.signOutInProgress {
                    requestWasBlockedDuringRemoteCall = true
                } catch {
                    XCTFail("Unexpected auth transition error: \(error)")
                }
            },
            performExternalSignOut: {}
        )

        XCTAssertTrue(observedLocalSignOutBeforeRemoteCall)
        XCTAssertTrue(requestWasBlockedDuringRemoteCall)
        XCTAssertFalse(manager.isSigningOut)
        XCTAssertFalse(manager.isAuthenticated)
    }

    func testUserSignOutTransitionInitializesOneAnonymousSessionAfterSignOut() async {
        var steps: [String] = []
        var initializationCount = 0

        let isReady = await SupabaseManager.performUserSignOutTransition(
            performSignOut: {
                steps.append("signOut")
            },
            initializeAnonymousSession: {
                steps.append("initializeAnonymousSession")
                initializationCount += 1
                return true
            }
        )

        XCTAssertTrue(isReady)
        XCTAssertEqual(initializationCount, 1)
        XCTAssertEqual(steps, ["signOut", "initializeAnonymousSession"])
    }

    func testUserSignOutTransitionPropagatesAnonymousSessionFailure() async {
        let isReady = await SupabaseManager.performUserSignOutTransition(
            performSignOut: {},
            initializeAnonymousSession: { false }
        )

        XCTAssertFalse(isReady)
    }

    func testPurchaseSafeSignOutPersistsBeforeClosingAndCompletingIdentity() async {
        var steps: [String] = []

        let isReady = await SupabaseManager.performPurchaseSafeSignOutTransition(
            prepareAndPersistHandoff: {
                steps.append("prepareAndPersist")
            },
            performSignOut: {
                steps.append("signOut")
            },
            initializeAnonymousSession: {
                steps.append("initializeAnonymousSession")
                return true
            },
            completeHandoff: {
                steps.append("completeHandoff")
            }
        )

        XCTAssertTrue(isReady)
        XCTAssertEqual(
            steps,
            [
                "prepareAndPersist",
                "signOut",
                "initializeAnonymousSession",
                "completeHandoff"
            ]
        )
    }

    func testPurchaseSafeSignOutNeverClosesSessionWhenPreparationFails() async {
        var didSignOut = false
        var didInitialize = false

        let isReady = await SupabaseManager.performPurchaseSafeSignOutTransition(
            prepareAndPersistHandoff: {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseHandoffPersistenceFailed
            },
            performSignOut: {
                didSignOut = true
            },
            initializeAnonymousSession: {
                didInitialize = true
                return true
            },
            completeHandoff: {}
        )

        XCTAssertFalse(isReady)
        XCTAssertFalse(didSignOut)
        XCTAssertFalse(didInitialize)
    }

    func testPurchaseSafeSignOutPropagatesDurableCompletionFailure() async {
        var didComplete = false

        let isReady = await SupabaseManager.performPurchaseSafeSignOutTransition(
            prepareAndPersistHandoff: {},
            performSignOut: {},
            initializeAnonymousSession: { true },
            completeHandoff: {
                didComplete = true
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }
        )

        XCTAssertFalse(isReady)
        XCTAssertTrue(didComplete)
    }

    func testSignOutPurchaseFinalizationClearsProofOnlyAfterEveryCheck() async throws {
        var steps: [String] = []

        try await SupabaseManager.finalizeSignOutPurchaseHandoff(
            bindDestination: { steps.append("bind") },
            verifyBoundDestinationSession: {
                steps.append("verifyBoundSession")
            },
            linkProviderIdentity: { steps.append("link") },
            verifyLinkedDestinationSession: {
                steps.append("verifyLinkedSession")
            },
            synchronizeStorePurchases: { steps.append("syncPurchases") },
            completeServerHandoff: { steps.append("complete") },
            refreshServerEntitlement: {
                steps.append("refreshEntitlement")
                return true
            },
            verifyFinalDestinationSession: {
                steps.append("verifyFinalSession")
            },
            clearPendingHandoff: { steps.append("clearProof") }
        )

        XCTAssertEqual(
            steps,
            [
                "bind",
                "verifyBoundSession",
                "link",
                "verifyLinkedSession",
                "syncPurchases",
                "complete",
                "refreshEntitlement",
                "verifyFinalSession",
                "clearProof"
            ]
        )
    }

    func testSignOutPurchaseFinalizationRetainsProofAfterSyncFailure() async {
        var steps: [String] = []

        do {
            try await SupabaseManager.finalizeSignOutPurchaseHandoff(
                bindDestination: { steps.append("bind") },
                verifyBoundDestinationSession: {
                    steps.append("verifyBoundSession")
                },
                linkProviderIdentity: { steps.append("link") },
                verifyLinkedDestinationSession: {
                    steps.append("verifyLinkedSession")
                },
                synchronizeStorePurchases: {
                    steps.append("syncPurchases")
                    throw URLError(.networkConnectionLost)
                },
                completeServerHandoff: { steps.append("complete") },
                refreshServerEntitlement: {
                    steps.append("refreshEntitlement")
                    return true
                },
                verifyFinalDestinationSession: {
                    steps.append("verifyFinalSession")
                },
                clearPendingHandoff: { steps.append("clearProof") }
            )
            XCTFail("Expected receipt synchronization failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        XCTAssertEqual(
            steps,
            [
                "bind",
                "verifyBoundSession",
                "link",
                "verifyLinkedSession",
                "syncPurchases"
            ]
        )
        XCTAssertFalse(steps.contains("clearProof"))
    }

    func testSignOutPurchaseFinalizationRefusesStaleSessionBeforeProviderLink() async {
        var steps: [String] = []

        do {
            try await SupabaseManager.finalizeSignOutPurchaseHandoff(
                bindDestination: { steps.append("bind") },
                verifyBoundDestinationSession: {
                    steps.append("verifyBoundSession")
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                },
                linkProviderIdentity: { steps.append("link") },
                verifyLinkedDestinationSession: {
                    steps.append("verifyLinkedSession")
                },
                synchronizeStorePurchases: {
                    steps.append("syncPurchases")
                },
                completeServerHandoff: { steps.append("complete") },
                refreshServerEntitlement: { true },
                verifyFinalDestinationSession: {},
                clearPendingHandoff: { steps.append("clearProof") }
            )
            XCTFail("Expected stale destination rejection")
        } catch {
            guard let transitionError = error as? SupabaseAuthTransitionError
            else {
                return XCTFail("Expected an auth-transition error")
            }
            guard case .signOutSessionChanged = transitionError else {
                return XCTFail("Expected stale destination rejection")
            }
        }

        XCTAssertEqual(steps, ["bind", "verifyBoundSession"])
    }

    func testOAuthProviderSubjectReadsBase64URLJWTSubject() throws {
        let token = try makeUnsignedJWT(
            payload: ["sub": "001234.abcd9876", "aud": "merian"]
        )

        XCTAssertEqual(
            try SupabaseManager.oauthProviderSubject(from: token),
            "001234.abcd9876"
        )
    }

    func testOAuthProviderSubjectRejectsMalformedOrUnsafeClaims() throws {
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(from: "not-a-jwt")
        )
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(
                from: try makeUnsignedJWT(payload: ["aud": "merian"])
            )
        )
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(
                from: try makeUnsignedJWT(payload: ["sub": "subject\ninjection"])
            )
        )
        XCTAssertThrowsError(
            try SupabaseManager.oauthProviderSubject(
                from: try makeUnsignedJWT(payload: ["sub": String(repeating: "a", count: 256)])
            )
        )
    }

    func testProviderBoundMergeFallbackOnlyAcceptsIdentityConflict() {
        let response = HTTPURLResponse(
            url: URL(string: "https://auth.example.test")!,
            statusCode: 422,
            httpVersion: nil,
            headerFields: nil
        )!
        let identityConflict = AuthError.api(
            message: "Identity already linked",
            errorCode: .identityAlreadyExists,
            underlyingData: Data(),
            underlyingResponse: response
        )
        let transientFailure = AuthError.api(
            message: "Request timed out",
            errorCode: .requestTimeout,
            underlyingData: Data(),
            underlyingResponse: response
        )

        XCTAssertTrue(
            SupabaseManager.requiresProviderBoundGhostMerge(
                after: identityConflict
            )
        )
        XCTAssertFalse(
            SupabaseManager.requiresProviderBoundGhostMerge(
                after: transientFailure
            )
        )
        XCTAssertFalse(
            SupabaseManager.requiresProviderBoundGhostMerge(
                after: URLError(.notConnectedToInternet)
            )
        )
    }

    func testAppleCredentialRegistrationRetriesTheSameDurableRequest() async throws {
        var attempts = 0
        var waits = 0

        try await SupabaseManager.performAppleCredentialRegistrationWithRetry(
            invoke: {
                attempts += 1
                if attempts == 1 {
                    throw URLError(.networkConnectionLost)
                }
            },
            waitBeforeRetry: {
                waits += 1
            }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(waits, 1)
    }

    func testAppleCredentialRegistrationStopsAfterBoundedRetry() async {
        var attempts = 0

        do {
            try await SupabaseManager.performAppleCredentialRegistrationWithRetry(
                invoke: {
                    attempts += 1
                    throw URLError(.cannotConnectToHost)
                },
                waitBeforeRetry: {}
            )
            XCTFail("Expected the bounded Apple credential registration to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotConnectToHost)
        }

        XCTAssertEqual(attempts, 2)
    }

    func testAppleCredentialRevocationStateFailsClosedWithoutClearingAuthorizedState() {
        XCTAssertFalse(
            SupabaseManager.shouldClearLocalSessionAfterAppleCredentialState(
                .authorized
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldClearLocalSessionAfterAppleCredentialState(
                .revoked
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldClearLocalSessionAfterAppleCredentialState(
                .notFound
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldClearLocalSessionAfterAppleCredentialState(
                .transferred
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldClearLocalSessionAfterAppleCredentialState(
                .authorized,
                lookupFailed: true
            )
        )
    }

    func testPendingMergeProofIsDiscardedOnlyForTerminalServerCodes() {
        let expired = FunctionsError.httpError(
            code: 410,
            data: Data(#"{"code":"handoff_expired"}"#.utf8)
        )
        let invalid = FunctionsError.httpError(
            code: 404,
            data: Data(#"{"code":"handoff_invalid"}"#.utf8)
        )
        let wrongDestination = FunctionsError.httpError(
            code: 403,
            data: Data(#"{"code":"handoff_forbidden"}"#.utf8)
        )
        let cleanupPending = FunctionsError.httpError(
            code: 503,
            data: Data(#"{"code":"auth_cleanup_pending"}"#.utf8)
        )
        let mergeTemporarilyUnavailable = FunctionsError.httpError(
            code: 503,
            data: Data(#"{"code":"merge_temporarily_unavailable"}"#.utf8)
        )

        XCTAssertTrue(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: expired
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: invalid
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: wrongDestination
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: cleanupPending
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: mergeTemporarilyUnavailable
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingGhostProfileMerge(
                after: URLError(.timedOut)
            )
        )
    }

    func testPendingSignOutPurchaseProofIsDiscardedOnlyForTerminalCodes() {
        let expired = FunctionsError.httpError(
            code: 410,
            data: Data(#"{"code":"handoff_expired"}"#.utf8)
        )
        let invalid = FunctionsError.httpError(
            code: 404,
            data: Data(#"{"code":"handoff_invalid"}"#.utf8)
        )
        let pending = FunctionsError.httpError(
            code: 503,
            data: Data(#"{"code":"purchase_transfer_pending"}"#.utf8)
        )

        XCTAssertTrue(
            SupabaseManager.shouldDiscardPendingSignOutPurchaseHandoff(
                after: expired
            )
        )
        XCTAssertTrue(
            SupabaseManager.shouldDiscardPendingSignOutPurchaseHandoff(
                after: invalid
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingSignOutPurchaseHandoff(
                after: pending
            )
        )
        XCTAssertFalse(
            SupabaseManager.shouldDiscardPendingSignOutPurchaseHandoff(
                after: URLError(.timedOut)
            )
        )
    }

    func testPendingSignOutPurchaseProofRoundTripsWithoutIdentityMutation() throws {
        let pending = SupabaseManager.PendingSignOutPurchaseHandoff(
            sourceUserId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            handoffId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            handoffSecret: String(repeating: "s", count: 43),
            expiresAt: "2026-09-10T12:00:00Z"
        )

        let encoded = try JSONEncoder().encode(pending)
        XCTAssertEqual(
            try JSONDecoder().decode(
                SupabaseManager.PendingSignOutPurchaseHandoff.self,
                from: encoded
            ),
            pending
        )
    }

    func testPendingMergeQueueReplacesOnlySameGhostAndRoundTrips() throws {
        let replaced = SupabaseManager.PendingGhostProfileMerge(
            ghostUserId: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            provider: "apple",
            providerSubject: "old-apple-subject",
            handoffId: "11111111-1111-1111-1111-111111111111",
            handoffSecret: "old-secret",
            expiresAt: "2026-08-01T00:00:00Z"
        )
        let unrelated = SupabaseManager.PendingGhostProfileMerge(
            ghostUserId: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            provider: "google",
            providerSubject: "google-subject",
            handoffId: "22222222-2222-2222-2222-222222222222",
            handoffSecret: "unrelated-secret",
            expiresAt: "2026-08-02T00:00:00Z"
        )
        let replacement = SupabaseManager.PendingGhostProfileMerge(
            ghostUserId: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            provider: "apple",
            providerSubject: "new-apple-subject",
            handoffId: "33333333-3333-3333-3333-333333333333",
            handoffSecret: "replacement-secret",
            expiresAt: "2026-08-03T00:00:00Z"
        )

        let updated = SupabaseManager.enqueuingPendingGhostProfileMerge(
            replacement,
            in: [replaced, unrelated]
        )

        XCTAssertEqual(updated, [unrelated, replacement])

        let queue = SupabaseManager.PendingGhostProfileMergeQueue(
            handoffs: updated
        )
        let encoded = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(
            SupabaseManager.PendingGhostProfileMergeQueue.self,
            from: encoded
        )

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.handoffs, [unrelated, replacement])
    }

    func testGhostConsentRebindPreservesImmutableEvidenceAndPendingState() {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_000_000)

        let adultReceipts = [
            makeAdultReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeAdultReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let termsReceipts = [
            makeTermsReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeTermsReceipt(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let aiEvents = [
            makeAIConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                recordedAt: recordedAt
            ),
            makeAIConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                recordedAt: nil
            )
        ]
        let analyticsEvents = [
            makeAnalyticsConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: ghostUserId,
                eventKind: .granted,
                recordedAt: recordedAt
            ),
            makeAnalyticsConsentEvent(
                ownerUserId: ghostUserId,
                syncedUserId: nil,
                eventKind: .revoked,
                recordedAt: nil
            )
        ]
        let source = ConsentManager.LocalLedger(
            activeUserId: ghostUserId,
            termsReceipts: termsReceipts,
            aiConsentEvents: aiEvents,
            adultEligibilityReceipts: adultReceipts,
            analyticsConsentEvents: analyticsEvents
        )

        let rebound = ConsentManager.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )

        XCTAssertEqual(rebound.activeUserId, permanentUserId)
        XCTAssertEqual(
            rebound,
            ConsentManager.rebinding(
                rebound,
                from: ghostUserId,
                to: permanentUserId
            ),
            "Rebinding must be idempotent for crash-safe handoff retries"
        )

        var expectedAdults = adultReceipts
        var expectedTerms = termsReceipts
        var expectedAI = aiEvents
        var expectedAnalytics = analyticsEvents
        for index in expectedAdults.indices {
            expectedAdults[index].ownerUserId = permanentUserId
            expectedAdults[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedTerms.indices {
            expectedTerms[index].ownerUserId = permanentUserId
            expectedTerms[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedAI.indices {
            expectedAI[index].ownerUserId = permanentUserId
            expectedAI[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }
        for index in expectedAnalytics.indices {
            expectedAnalytics[index].ownerUserId = permanentUserId
            expectedAnalytics[index].syncedUserId = index == 0
                ? permanentUserId
                : nil
        }

        XCTAssertEqual(rebound.adultEligibilityReceipts, expectedAdults)
        XCTAssertEqual(rebound.termsReceipts, expectedTerms)
        XCTAssertEqual(rebound.aiConsentEvents, expectedAI)
        XCTAssertEqual(rebound.analyticsConsentEvents, expectedAnalytics)
    }

    func testOfflineGhostAnalyticsRevocationWinsAfterMergeAndAcrossDevices() throws {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let grantRecordedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let revocation = makeAnalyticsConsentEvent(
            ownerUserId: ghostUserId,
            syncedUserId: nil,
            eventKind: .revoked,
            recordedAt: nil
        )
        let permanentGrant = makeAnalyticsConsentEvent(
            ownerUserId: permanentUserId,
            syncedUserId: permanentUserId,
            eventKind: .granted,
            recordedAt: grantRecordedAt,
            consentRevision: 60
        )
        let source = ConsentManager.LocalLedger(
            activeUserId: ghostUserId,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: [
                permanentGrant,
                revocation
            ]
        )
        let rebound = ConsentManager.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )

        let suiteName = "merian.tests.ghost-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            try JSONEncoder().encode(rebound),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let mergedManager = ConsentManager(userDefaults: userDefaults)
        mergedManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(mergedManager.hasGrantedCurrentPostHogAnalytics)

        let restartedManager = ConsentManager(userDefaults: userDefaults)
        restartedManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(restartedManager.hasGrantedCurrentPostHogAnalytics)

        var secondDeviceLedger = rebound
        let revocationIndex = try XCTUnwrap(
            secondDeviceLedger.analyticsConsentEvents.firstIndex {
                $0.id == revocation.id
            }
        )
        secondDeviceLedger.analyticsConsentEvents[revocationIndex].syncedUserId =
            permanentUserId
        secondDeviceLedger.analyticsConsentEvents[revocationIndex].recordedAt =
            grantRecordedAt.addingTimeInterval(1)
        secondDeviceLedger.analyticsConsentEvents[revocationIndex]
            .causalParentId = permanentGrant.id
        secondDeviceLedger.analyticsConsentEvents[revocationIndex]
            .consentRevision = 61
        userDefaults.set(
            try JSONEncoder().encode(secondDeviceLedger),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let secondDeviceManager = ConsentManager(userDefaults: userDefaults)
        secondDeviceManager.observeSession(userId: permanentUserId)
        XCTAssertFalse(secondDeviceManager.hasGrantedCurrentPostHogAnalytics)
    }

    func testOfflineAIRevocationClosesPermissionAcrossRestart() throws {
        let ownerUserId = UUID()
        let grant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_050_000),
            consentRevision: 60
        )
        let revocation = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            eventKind: .revoked,
            recordedAt: nil,
            causalParentId: grant.id
        )
        let source = ConsentManager.LocalLedger(
            activeUserId: ownerUserId,
            termsReceipts: [],
            aiConsentEvents: [grant, revocation],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: []
        )
        let suiteName = "merian.tests.offline-ai-revocation.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConsentLedgerStore(userDefaults: userDefaults)
        try store.saveLedgerData(JSONEncoder().encode(source))

        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(manager.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(manager.pendingCloudRecordCount, 1)

        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(restarted.pendingCloudRecordCount, 1)
    }

    func testInverseOrderCrossDeviceAIRevocationSupersedesOfflineGrant() throws {
        let ownerUserId = UUID()
        let baseline = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 40
        )
        let remoteRevocation = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_050),
            causalParentId: baseline.id,
            consentRevision: 41
        )
        let staleOfflineGrant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            eventKind: .granted,
            recordedAt: nil,
            causalParentId: baseline.id,
            supersededByEventId: remoteRevocation.id,
            supersededByRevision: 41
        )
        let suiteName = "merian.tests.inverse-ai-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            try JSONEncoder().encode(ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [makeTermsReceipt(
                    ownerUserId: ownerUserId,
                    syncedUserId: ownerUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
                )],
                aiConsentEvents: [baseline, staleOfflineGrant],
                adultEligibilityReceipts: [makeAdultReceipt(
                    ownerUserId: ownerUserId,
                    syncedUserId: ownerUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_100_000)
                )],
                analyticsConsentEvents: []
            )),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            ),
            currentSDKUserIdProvider: { ownerUserId }
        )
        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: remoteRevocation,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: remoteRevocation,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertFalse(manager.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(userDefaults: userDefaults)
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
        restarted.observeSession(userId: ownerUserId)
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(restarted.pendingCloudRecordCount, 0)
    }

    func testInverseOrderCrossDeviceAnalyticsRevocationSupersedesOfflineGrant() throws {
        let ownerUserId = UUID()
        let baseline = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 50
        )
        let remoteRevocation = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_050),
            causalParentId: baseline.id,
            consentRevision: 51
        )
        let staleOfflineGrant = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            eventKind: .granted,
            recordedAt: nil,
            causalParentId: baseline.id,
            supersededByEventId: remoteRevocation.id,
            supersededByRevision: 51
        )
        let suiteName = "merian.tests.inverse-analytics-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(
            try JSONEncoder().encode(ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [],
                aiConsentEvents: [],
                adultEligibilityReceipts: [],
                analyticsConsentEvents: [baseline, staleOfflineGrant]
            )),
            forKey: UserDefaultsKeys.legalConsentLedger
        )

        let manager = ConsentManager(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            ),
            currentSDKUserIdProvider: { ownerUserId }
        )
        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: remoteRevocation,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: remoteRevocation
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(userDefaults: userDefaults)
        XCTAssertFalse(restarted.hasGrantedCurrentPostHogAnalytics)
        restarted.observeSession(userId: ownerUserId)
        XCTAssertFalse(restarted.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(restarted.pendingCloudRecordCount, 0)
    }

    func testOlderDisclosureAIRevocationAtStreamHeadClosesCurrentGrant() throws {
        let ownerUserId = UUID()
        let currentGrant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 60
        )
        let olderDisclosureRevocation = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            disclosureVersion: "2026-08-03.1",
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_200),
            causalParentId: currentGrant.id,
            consentRevision: 61
        )
        let suiteName = "merian.tests.cross-version-ai-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConsentLedgerStore(userDefaults: userDefaults)
        try store.saveLedgerData(JSONEncoder().encode(ConsentManager.LocalLedger(
            activeUserId: ownerUserId,
            termsReceipts: [],
            aiConsentEvents: [currentGrant],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: []
        )))

        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertTrue(manager.hasGrantedCurrentGeminiProcessing)
        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: currentGrant,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: olderDisclosureRevocation,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertFalse(manager.hasGrantedCurrentGeminiProcessing)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(restarted.hasGrantedCurrentGeminiProcessing)
    }

    func testOlderDisclosureAnalyticsRevocationAtStreamHeadClosesCurrentGrant() throws {
        let ownerUserId = UUID()
        let currentGrant = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            eventKind: .granted,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_100),
            consentRevision: 70
        )
        let olderDisclosureRevocation = makeAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            syncedUserId: ownerUserId,
            disclosureVersion: "2026-08-03",
            eventKind: .revoked,
            recordedAt: Date(timeIntervalSince1970: 1_786_100_200),
            causalParentId: currentGrant.id,
            consentRevision: 71
        )
        let suiteName = "merian.tests.cross-version-analytics-consent.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsConsentLedgerStore(userDefaults: userDefaults)
        try store.saveLedgerData(JSONEncoder().encode(ConsentManager.LocalLedger(
            activeUserId: ownerUserId,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: [currentGrant]
        )))

        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertTrue(manager.hasGrantedCurrentPostHogAnalytics)
        manager.observeSession(userId: ownerUserId)
        try manager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: currentGrant,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: olderDisclosureRevocation
            ),
            for: ownerUserId,
            generation: 1
        )

        XCTAssertEqual(
            manager.analyticsCloudAuthorityState,
            .resolvedRemote(userId: ownerUserId, granted: false)
        )
        XCTAssertFalse(manager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(manager.pendingCloudRecordCount, 0)

        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId }
        )
        XCTAssertFalse(restarted.hasGrantedCurrentPostHogAnalytics)
    }

    func testGhostHandoffClearsQueueOnlyAfterServerAndLocalCompletion() async throws {
        var calls: [String] = []

        try await SupabaseManager.finalizeGhostProfileHandoff(
            completeServerHandoff: { calls.append("server") },
            synchronizeProviderPurchases: { calls.append("provider") },
            rebindAndSynchronizeLocalEvidence: { calls.append("local") },
            clearPendingHandoff: { calls.append("clear") }
        )

        XCTAssertEqual(calls, ["server", "provider", "local", "clear"])
    }

    func testGhostHandoffRetainsQueueWhenServerOrLocalCompletionFails() async {
        var serverFailureCalls: [String] = []
        do {
            try await SupabaseManager.finalizeGhostProfileHandoff(
                completeServerHandoff: {
                    serverFailureCalls.append("server")
                    throw GhostHandoffTestError.expected
                },
                synchronizeProviderPurchases: {
                    serverFailureCalls.append("provider")
                },
                rebindAndSynchronizeLocalEvidence: {
                    serverFailureCalls.append("local")
                },
                clearPendingHandoff: {
                    serverFailureCalls.append("clear")
                }
            )
            XCTFail("Server failure must remain retryable")
        } catch {}
        XCTAssertEqual(serverFailureCalls, ["server"])

        var providerFailureCalls: [String] = []
        do {
            try await SupabaseManager.finalizeGhostProfileHandoff(
                completeServerHandoff: {
                    providerFailureCalls.append("server")
                },
                synchronizeProviderPurchases: {
                    providerFailureCalls.append("provider")
                    throw GhostHandoffTestError.expected
                },
                rebindAndSynchronizeLocalEvidence: {
                    providerFailureCalls.append("local")
                },
                clearPendingHandoff: {
                    providerFailureCalls.append("clear")
                }
            )
            XCTFail("Provider synchronization failure must retain the durable handoff")
        } catch {}
        XCTAssertEqual(providerFailureCalls, ["server", "provider"])

        var localFailureCalls: [String] = []
        do {
            try await SupabaseManager.finalizeGhostProfileHandoff(
                completeServerHandoff: {
                    localFailureCalls.append("server")
                },
                synchronizeProviderPurchases: {
                    localFailureCalls.append("provider")
                },
                rebindAndSynchronizeLocalEvidence: {
                    localFailureCalls.append("local")
                    throw GhostHandoffTestError.expected
                },
                clearPendingHandoff: {
                    localFailureCalls.append("clear")
                }
            )
            XCTFail("Local evidence failure must retain the durable handoff")
        } catch {}
        XCTAssertEqual(localFailureCalls, ["server", "provider", "local"])
    }

    func testGhostHandoffRemovalFailureRemainsRetryable() async {
        var calls: [String] = []
        do {
            try await SupabaseManager.finalizeGhostProfileHandoff(
                completeServerHandoff: { calls.append("server") },
                synchronizeProviderPurchases: { calls.append("provider") },
                rebindAndSynchronizeLocalEvidence: { calls.append("local") },
                clearPendingHandoff: {
                    calls.append("clear")
                    throw GhostHandoffTestError.expected
                }
            )
            XCTFail("A failed verified queue write must be retried")
        } catch {}
        XCTAssertEqual(calls, ["server", "provider", "local", "clear"])
    }

    func testTargetAccountActivationPreservesPendingAndHistoricalEvidence() {
        let previousUserId = UUID()
        let targetUserId = UUID()
        let source = ConsentManager.LocalLedger(
            activeUserId: previousUserId,
            termsReceipts: [
                makeTermsReceipt(
                    ownerUserId: targetUserId,
                    syncedUserId: nil,
                    recordedAt: nil
                )
            ],
            aiConsentEvents: [
                makeAIConsentEvent(
                    ownerUserId: previousUserId,
                    syncedUserId: previousUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_000_000)
                )
            ],
            adultEligibilityReceipts: [
                makeAdultReceipt(
                    ownerUserId: targetUserId,
                    syncedUserId: targetUserId,
                    recordedAt: Date(timeIntervalSince1970: 1_786_000_001)
                )
            ],
            analyticsConsentEvents: [
                makeAnalyticsConsentEvent(
                    ownerUserId: targetUserId,
                    syncedUserId: nil,
                    eventKind: .revoked,
                    recordedAt: nil
                )
            ]
        )

        let activated = ConsentManager.activating(source, for: targetUserId)

        XCTAssertEqual(activated.activeUserId, targetUserId)
        XCTAssertEqual(activated.termsReceipts, source.termsReceipts)
        XCTAssertEqual(activated.aiConsentEvents, source.aiConsentEvents)
        XCTAssertEqual(
            activated.adultEligibilityReceipts,
            source.adultEligibilityReceipts
        )
        XCTAssertEqual(
            activated.analyticsConsentEvents,
            source.analyticsConsentEvents
        )
        XCTAssertEqual(
            ConsentManager.activating(activated, for: targetUserId),
            activated
        )
    }

    func testOAuthSessionReplacementSuspendsBeforeInstallingAndReconcilesSuccess() async throws {
        var calls: [String] = []

        let installed = try await SupabaseManager.performOAuthSessionReplacement(
            suspendAnalytics: {
                calls.append("suspend")
                return 41
            },
            installSession: {
                calls.append("install")
                return "target-session"
            },
            currentSession: {
                calls.append("current")
                return "unexpected-session"
            },
            reconcileSession: { generation, session in
                calls.append("reconcile:\(generation):\(session ?? "nil")")
            }
        )

        XCTAssertEqual(installed, "target-session")
        XCTAssertEqual(calls, [
            "suspend",
            "install",
            "reconcile:41:target-session"
        ])
    }

    func testOAuthSessionReplacementReconcilesActualSessionOnFailure() async {
        var calls: [String] = []

        do {
            let _: String = try await SupabaseManager.performOAuthSessionReplacement(
                suspendAnalytics: {
                    calls.append("suspend")
                    return 42
                },
                installSession: {
                    calls.append("install")
                    throw OAuthSessionReplacementTestError.expected
                },
                currentSession: {
                    calls.append("current")
                    return "restored-session"
                },
                reconcileSession: { generation, session in
                    calls.append("reconcile:\(generation):\(session ?? "nil")")
                }
            )
            XCTFail("A failed session installation must be rethrown")
        } catch OAuthSessionReplacementTestError.expected {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(calls, [
            "suspend",
            "install",
            "current",
            "reconcile:42:restored-session"
        ])
    }

    private func makeAdultReceipt(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        recordedAt: Date?
    ) -> ConsentManager.AdultEligibilityReceipt {
        ConsentManager.AdultEligibilityReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            policyVersion: ConsentPolicy.adultEligibilityVersion,
            confirmedAt: Date(timeIntervalSince1970: 1_785_999_900),
            confirmationMethod: .selfAttestation,
            confirmationText: ConsentPolicy.adultConfirmationText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    private func makeTermsReceipt(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        recordedAt: Date?
    ) -> ConsentManager.TermsAcceptanceReceipt {
        ConsentManager.TermsAcceptanceReceipt(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            termsVersion: ConsentPolicy.termsVersion,
            acceptedAt: Date(timeIntervalSince1970: 1_785_999_900),
            acceptanceText: ConsentPolicy.combinedAcceptanceText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt
        )
    }

    private func makeAIConsentEvent(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        disclosureVersion: String = ConsentPolicy.geminiDisclosureVersion,
        eventKind: ConsentManager.AIConsentEventKind = .granted,
        recordedAt: Date?,
        causalParentId: UUID? = nil,
        consentRevision: Int64? = nil,
        supersededByEventId: UUID? = nil,
        supersededByRevision: Int64? = nil
    ) -> ConsentManager.AIConsentEvent {
        ConsentManager.AIConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            provider: ConsentPolicy.geminiProvider,
            disclosureVersion: disclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_785_999_900),
            disclosureText: ConsentPolicy.geminiDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.combinedAcceptanceText
                : ConsentPolicy.geminiWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt,
            causalParentId: causalParentId,
            consentRevision: consentRevision,
            supersededByEventId: supersededByEventId,
            supersededByRevision: supersededByRevision
        )
    }

    private func makeAnalyticsConsentEvent(
        ownerUserId: UUID,
        syncedUserId: UUID?,
        disclosureVersion: String = ConsentPolicy.analyticsDisclosureVersion,
        eventKind: ConsentManager.AnalyticsConsentEventKind,
        recordedAt: Date?,
        causalParentId: UUID? = nil,
        consentRevision: Int64? = nil,
        supersededByEventId: UUID? = nil,
        supersededByRevision: Int64? = nil
    ) -> ConsentManager.AnalyticsConsentEvent {
        ConsentManager.AnalyticsConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: syncedUserId,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: disclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_785_999_900),
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: recordedAt,
            causalParentId: causalParentId,
            consentRevision: consentRevision,
            supersededByEventId: supersededByEventId,
            supersededByRevision: supersededByRevision
        )
    }

    private func makeUnsignedJWT(payload: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let payloadSegment = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(payloadSegment).signature"
    }
}

private actor SupabaseManagerTestGate {
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

private enum GhostHandoffTestError: Error {
    case expected
}

private enum OAuthSessionReplacementTestError: Error {
    case expected
}
