import Foundation
import SwiftData

struct AccountLocalDataDependencies {
    let purgeAllData: @MainActor (
        _ modelContext: ModelContext,
        _ resetDerivedState: @MainActor () -> Void
    ) -> Bool

    static var live: Self {
        Self(
            purgeAllData: { modelContext, resetDerivedState in
                ScanRepository.shared.purgeAllData(
                    modelContext: modelContext,
                    resetDerivedState: resetDerivedState
                )
            }
        )
    }
}

@MainActor
struct AccountDeletionDependencies {
    let isPurchaseContinuityPending: @MainActor () -> Bool
    let hasPendingPurchaseContinuityFailClosed: @MainActor () -> Bool
    let isRecoveryPending: @MainActor () -> Bool
    let deleteAccount: @MainActor (
        _ purgeLocalData: @MainActor @escaping () -> Bool
    ) async throws -> Void
    let resumeDeletion: @MainActor (
        _ purgeLocalData: @MainActor @escaping () -> Bool
    ) async -> Bool
    let stableErrorCode: @MainActor (_ error: Error) -> String?
    let logFailure: @MainActor (_ error: Error) -> Void

    static func live(supabase: SupabaseManager) -> Self {
        Self(
            isPurchaseContinuityPending: {
                RevenueCatManager.shared.isPurchaseIdentityHandoffPending
            },
            hasPendingPurchaseContinuityFailClosed: {
                supabase.hasPendingPurchaseIdentityHandoffFailClosed()
            },
            isRecoveryPending: {
                AccountDeletionLocalCleanupStore.isPending()
            },
            deleteAccount: { purgeLocalData in
                _ = try await supabase.deleteCurrentAccount(
                    purgeLocalData: purgeLocalData
                )
            },
            resumeDeletion: { purgeLocalData in
                await supabase.resumePendingAccountDeletionLocalCleanup(
                    purgeLocalData: purgeLocalData
                )
            },
            stableErrorCode: { error in
                EdgeFunctionErrorPolicy.stableCode(from: error)
            },
            logFailure: { error in
                MerianLog.general.error(
                    "Account deletion failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
            }
        )
    }
}

@MainActor
struct SettingsSignOutDependencies {
    let isPurchaseContinuityPending: @MainActor () -> Bool
    let transitionToGhostSession: @MainActor () async -> Bool

    static func live(supabase: SupabaseManager) -> Self {
        Self(
            isPurchaseContinuityPending: {
                RevenueCatManager.shared.isPurchaseIdentityHandoffPending
            },
            transitionToGhostSession: {
                await supabase.transitionToGhostSession()
            }
        )
    }
}
