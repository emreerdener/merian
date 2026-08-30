import XCTest

@testable import Merian

@MainActor
final class AccountSettingsViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    func testDeleteEligibilityPreservesConfirmationAndTransitionFences() {
        let viewModel = DeleteAccountViewModel(
            dependencies: makeDeletionDependencies()
        )

        XCTAssertFalse(
            viewModel.isDeleteEnabled(isAuthTransitionInProgress: false)
        )

        viewModel.confirmationText = "DELETE"
        XCTAssertTrue(
            viewModel.isDeleteEnabled(isAuthTransitionInProgress: false)
        )
        XCTAssertFalse(
            viewModel.isDeleteEnabled(isAuthTransitionInProgress: true)
        )
    }

    func testDeleteRefusesFailClosedPurchaseContinuityBeforeMutation() async {
        var deleteCallCount = 0
        let viewModel = DeleteAccountViewModel(
            dependencies: makeDeletionDependencies(
                hasPendingPurchaseContinuityFailClosed: { true },
                deleteAccount: { _ in deleteCallCount += 1 }
            )
        )

        let didDelete = await viewModel.deleteAccount {
            XCTFail("Local data must not be purged while purchase continuity is pending")
            return true
        }

        XCTAssertFalse(didDelete)
        XCTAssertEqual(deleteCallCount, 0)
        XCTAssertEqual(
            viewModel.errorMessage,
            DeleteAccountViewModel.purchaseContinuityMessage
        )
    }

    func testFreshDeletionDelegatesPurgeAndReportsSuccess() async {
        var didPurge = false
        var deleteCallCount = 0
        let viewModel = DeleteAccountViewModel(
            dependencies: makeDeletionDependencies(
                deleteAccount: { purgeLocalData in
                    deleteCallCount += 1
                    XCTAssertTrue(purgeLocalData())
                }
            )
        )

        let didDelete = await viewModel.deleteAccount {
            didPurge = true
            return true
        }

        XCTAssertTrue(didDelete)
        XCTAssertTrue(didPurge)
        XCTAssertEqual(deleteCallCount, 1)
        XCTAssertTrue(viewModel.isDeleting)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testPendingRecoveryUsesResumePathAndPreservesRetryMessage() async {
        var deleteCallCount = 0
        var resumeCallCount = 0
        let viewModel = DeleteAccountViewModel(
            dependencies: makeDeletionDependencies(
                isRecoveryPending: { true },
                deleteAccount: { _ in deleteCallCount += 1 },
                resumeDeletion: { _ in
                    resumeCallCount += 1
                    return false
                }
            )
        )

        let didDelete = await viewModel.deleteAccount { true }

        XCTAssertFalse(didDelete)
        XCTAssertEqual(deleteCallCount, 0)
        XCTAssertEqual(resumeCallCount, 1)
        XCTAssertEqual(
            viewModel.errorMessage,
            DeleteAccountViewModel.pendingMessage
        )
    }

    func testDeletionErrorUsesStablePurchaseContinuityCode() async {
        var loggedFailureCount = 0
        let viewModel = DeleteAccountViewModel(
            dependencies: makeDeletionDependencies(
                deleteAccount: { _ in throw StubError.failed },
                stableErrorCode: { _ in "purchase_continuity_pending" },
                logFailure: { _ in loggedFailureCount += 1 }
            )
        )

        let didDelete = await viewModel.deleteAccount { true }

        XCTAssertFalse(didDelete)
        XCTAssertEqual(loggedFailureCount, 1)
        XCTAssertEqual(
            viewModel.errorMessage,
            DeleteAccountViewModel.purchaseContinuityMessage
        )
    }

    func testOverlappingDeletionCannotMutateActiveAttemptFeedback() async {
        var purchaseContinuityIsPending = false
        var pendingDeletion: CheckedContinuation<Void, any Error>?
        let viewModel = DeleteAccountViewModel(
            dependencies: makeDeletionDependencies(
                hasPendingPurchaseContinuityFailClosed: {
                    purchaseContinuityIsPending
                },
                deleteAccount: { _ in
                    try await withCheckedThrowingContinuation {
                        pendingDeletion = $0
                    }
                }
            )
        )

        let activeTask = Task {
            await viewModel.deleteAccount { true }
        }
        while pendingDeletion == nil {
            await Task.yield()
        }

        purchaseContinuityIsPending = true
        let overlappingResult = await viewModel.deleteAccount { true }
        XCTAssertFalse(overlappingResult)
        XCTAssertNil(viewModel.errorMessage)

        pendingDeletion?.resume(returning: ())
        let activeResult = await activeTask.value
        XCTAssertTrue(activeResult)
    }

    func testSignOutFailureUsesPostTransitionAnonymousState() async {
        let viewModel = SettingsSignOutViewModel(
            dependencies: SettingsSignOutDependencies(
                isPurchaseContinuityPending: { false },
                transitionToGhostSession: { false }
            )
        )

        await viewModel.signOut(isAnonymousSession: { true })

        XCTAssertTrue(viewModel.showError)
        XCTAssertEqual(
            viewModel.errorMessage,
            SignOutPresentationPolicy.incompleteMessage(
                isAnonymousSession: true
            )
        )
        XCTAssertFalse(viewModel.isSigningOut)
    }

    private func makeDeletionDependencies(
        isPurchaseContinuityPending: @escaping @MainActor () -> Bool = {
            false
        },
        hasPendingPurchaseContinuityFailClosed:
            @escaping @MainActor () -> Bool = { false },
        isRecoveryPending: @escaping @MainActor () -> Bool = { false },
        deleteAccount: @escaping @MainActor (
            @MainActor @escaping () -> Bool
        ) async throws -> Void = { _ in },
        resumeDeletion: @escaping @MainActor (
            @MainActor @escaping () -> Bool
        ) async -> Bool = { _ in true },
        stableErrorCode: @escaping @MainActor (Error) -> String? = { _ in
            nil
        },
        logFailure: @escaping @MainActor (Error) -> Void = { _ in }
    ) -> AccountDeletionDependencies {
        AccountDeletionDependencies(
            isPurchaseContinuityPending: isPurchaseContinuityPending,
            hasPendingPurchaseContinuityFailClosed:
                hasPendingPurchaseContinuityFailClosed,
            isRecoveryPending: isRecoveryPending,
            deleteAccount: deleteAccount,
            resumeDeletion: resumeDeletion,
            stableErrorCode: stableErrorCode,
            logFailure: logFailure
        )
    }
}
