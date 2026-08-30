import Observation
import RevenueCat

@MainActor
@Observable
final class PaywallViewModel {
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    var operationErrorMessage: String?

    private let dependencies: PaywallDependencies

    init(dependencies: PaywallDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func fetchOfferings() async {
        await dependencies.fetchOfferings()
    }

    func purchase(_ package: Package) async -> Bool {
        guard !isPurchasing, !isRestoring else { return false }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await dependencies.purchase(package)
            return dependencies.isSubscribed()
        } catch {
            operationErrorMessage = error.localizedDescription
            dependencies.logPurchaseFailure(error)
            return false
        }
    }

    func restorePurchases() async -> Bool {
        guard !isRestoring, !isPurchasing else { return false }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await dependencies.restorePurchases()
            return dependencies.isSubscribed()
        } catch {
            operationErrorMessage = error.localizedDescription
            dependencies.logRestoreFailure(error)
            return false
        }
    }
}
