import Observation

@MainActor
@Observable
final class SettingsSignOutViewModel {
    var showConfirmation = false
    var showError = false
    private(set) var isSigningOut = false
    private(set) var errorMessage = SignOutPresentationPolicy
        .incompleteMessage(isAnonymousSession: false)

    private let dependencies: SettingsSignOutDependencies

    init(dependencies: SettingsSignOutDependencies) {
        self.dependencies = dependencies
    }

    var isPurchaseContinuityPending: Bool {
        dependencies.isPurchaseContinuityPending()
    }

    func signOut(isAnonymousSession: @MainActor () -> Bool) async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        guard await dependencies.transitionToGhostSession() else {
            errorMessage = SignOutPresentationPolicy.incompleteMessage(
                isAnonymousSession: isAnonymousSession()
            )
            showError = true
            return
        }
    }
}
