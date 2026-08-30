import Observation

@MainActor
@Observable
final class DeleteAccountViewModel {
    static let pendingMessage =
        "Account deletion is still being confirmed. Keep Naturebook open and connected; it will retry safely."
    static let purchaseContinuityMessage =
        "Finish signing out before deleting this account."
    static let genericFailureMessage =
        "Failed to delete account. Please try again or contact support."

    var confirmationText = ""
    private(set) var isDeleting = false
    var errorMessage: String?

    private let dependencies: AccountDeletionDependencies

    init(dependencies: AccountDeletionDependencies) {
        self.dependencies = dependencies
    }

    var isPurchaseContinuityPending: Bool {
        dependencies.isPurchaseContinuityPending()
    }

    var isRecoveryPending: Bool {
        dependencies.isRecoveryPending()
    }

    func isDeleteEnabled(isAuthTransitionInProgress: Bool) -> Bool {
        confirmationText == "DELETE" &&
            !isPurchaseContinuityPending &&
            !isRecoveryPending &&
            !isAuthTransitionInProgress
    }

    func deleteAccount(
        purgeLocalData: @MainActor @escaping () -> Bool
    ) async -> Bool {
        guard !isDeleting else { return false }
        guard !dependencies.hasPendingPurchaseContinuityFailClosed() else {
            errorMessage = Self.purchaseContinuityMessage
            return false
        }

        isDeleting = true
        errorMessage = nil

        do {
            if dependencies.isRecoveryPending() {
                guard await dependencies.resumeDeletion(purgeLocalData) else {
                    errorMessage = Self.pendingMessage
                    isDeleting = false
                    return false
                }
            } else {
                try await dependencies.deleteAccount(purgeLocalData)
            }
            return true
        } catch {
            dependencies.logFailure(error)
            if dependencies.isRecoveryPending() {
                errorMessage = Self.pendingMessage
            } else if dependencies.stableErrorCode(error) ==
                "purchase_continuity_pending" {
                errorMessage = Self.purchaseContinuityMessage
            } else {
                errorMessage = Self.genericFailureMessage
            }
            isDeleting = false
            return false
        }
    }
}
