import Foundation
import Observation

/// Shared prompt state. Dismissal never clears a compatibility pause. Only a
/// different installed release/build permits the affected operation to retry.
@MainActor
@Observable final class AppUpdateCoordinator {
    private(set) var showsPrompt = false
    private let store: ClientUpdateRequirementStore
    private let currentAccountID: @MainActor () -> UUID?
    private let build: String
    private var dismissedAccounts: Set<UUID> = []

    init(
        defaults: UserDefaults = .standard,
        buildIdentity: String? = nil,
        currentAccountID: @escaping @MainActor () -> UUID?
    ) {
        store = ClientUpdateRequirementStore(defaults: defaults)
        self.currentAccountID = currentAccountID
        build = buildIdentity ?? ["CFBundleShortVersionString", "CFBundleVersion"]
            .map { Bundle.main.object(forInfoDictionaryKey: $0) as? String ?? "unknown" }
            .joined(separator: ":")
    }

    func record(
        _ scope: ClientUpdateRequirementStore.Scope,
        accountID: UUID? = nil
    ) {
        guard let current = currentAccountID(),
              accountID == nil || accountID == current else { return }
        store.record(scope, accountID: current, build: build)
        refresh()
    }

    func requiresUpdate(
        _ scope: ClientUpdateRequirementStore.Scope,
        accountID: UUID
    ) -> Bool {
        store.blockedBuild(for: scope, accountID: accountID) == build
    }

    var shouldRetryHistoryAfterUpdate: Bool {
        guard let accountID = currentAccountID(),
              let blocked = store.blockedBuild(for: .history, accountID: accountID) else {
            return false
        }
        return blocked != build
    }

    func historySucceeded(accountID: UUID) {
        guard accountID == currentAccountID(),
              store.blockedBuild(for: .history, accountID: accountID) != build else { return }
        // An overlapping successful sync must not erase a newer denial from
        // this same installed build. Only post-update recovery clears it.
        store.clear(.history, accountID: accountID)
        refresh()
    }

    /// A manual retry reopens the prompt without resetting the queue's retry
    /// budget, claiming funding, or releasing server-completed ownership.
    func blocksRetry(errorCode: String?) -> Bool {
        let scope: ClientUpdateRequirementStore.Scope
        switch errorCode {
        case "client_update_required": scope = .identification
        case "server_result_local_recovery_update_required": scope = .history
        default: return false
        }
        guard let accountID = currentAccountID(),
              requiresUpdate(scope, accountID: accountID) else { return false }
        dismissedAccounts.remove(accountID)
        refresh()
        return true
    }

    func refresh() {
        guard let accountID = currentAccountID() else {
            showsPrompt = false
            return
        }
        showsPrompt = !dismissedAccounts.contains(accountID)
            && ClientUpdateRequirementStore.Scope.allCases.contains {
                requiresUpdate($0, accountID: accountID)
            }
    }

    func dismiss() {
        if let accountID = currentAccountID() { dismissedAccounts.insert(accountID) }
        showsPrompt = false
    }
}
