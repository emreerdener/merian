import Observation

@MainActor
@Observable
final class ManagePlanViewModel {
    private(set) var isRestoring = false
    var operationErrorMessage: String?

    private let dependencies: ManagePlanDependencies

    init(dependencies: ManagePlanDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await dependencies.restorePurchases()
        } catch {
            operationErrorMessage = error.localizedDescription
            dependencies.logRestoreFailure(error)
        }
    }

    func presentCodeRedemption() {
        guard !isRestoring else { return }

        do {
            try dependencies.presentCodeRedemption()
        } catch {
            operationErrorMessage = error.localizedDescription
            dependencies.logRedemptionFailure(error)
        }
    }
}
