import RevenueCat

@MainActor
struct PaywallDependencies {
    let fetchOfferings: @MainActor () async -> Void
    let purchase: @MainActor (_ package: Package) async throws -> Void
    let restorePurchases: @MainActor () async throws -> Void
    let isSubscribed: @MainActor () -> Bool
    let logPurchaseFailure: @MainActor (_ error: Error) -> Void
    let logRestoreFailure: @MainActor (_ error: Error) -> Void

    static var live: Self {
        let manager = RevenueCatManager.shared
        return Self(
            fetchOfferings: {
                await manager.fetchOfferings()
            },
            purchase: { package in
                try await manager.purchase(package)
            },
            restorePurchases: {
                try await manager.restorePurchases()
            },
            isSubscribed: {
                manager.isSubscribed
            },
            logPurchaseFailure: { error in
                MerianLog.general.error(
                    "In-app purchase failed: \(error.localizedDescription, privacy: .private)"
                )
            },
            logRestoreFailure: { error in
                MerianLog.general.error(
                    "Purchase restore failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        )
    }
}

@MainActor
struct ManagePlanDependencies {
    let restorePurchases: @MainActor () async throws -> Void
    let presentCodeRedemption: @MainActor () throws -> Void
    let logRestoreFailure: @MainActor (_ error: Error) -> Void
    let logRedemptionFailure: @MainActor (_ error: Error) -> Void

    static var live: Self {
        let manager = RevenueCatManager.shared
        return Self(
            restorePurchases: {
                try await manager.restorePurchases()
            },
            presentCodeRedemption: {
                try manager.presentCodeRedemptionSheet()
            },
            logRestoreFailure: { error in
                MerianLog.general.error(
                    "Failed to restore purchases: \(error.localizedDescription, privacy: .private)"
                )
            },
            logRedemptionFailure: { error in
                MerianLog.general.error(
                    "Failed to present code redemption: \(error.localizedDescription, privacy: .private)"
                )
            }
        )
    }
}

@MainActor
struct PlanCardDependencies {
    let showManageSubscriptions: @MainActor () -> Void

    static var live: Self {
        Self(
            showManageSubscriptions: {
                RevenueCatManager.shared.showManageSubscriptions()
            }
        )
    }
}
