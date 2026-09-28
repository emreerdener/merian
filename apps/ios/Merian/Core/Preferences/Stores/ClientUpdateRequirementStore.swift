import Foundation

/// Compatibility pauses are account- and installed-build-specific. No scan or
/// response content is persisted here; queued scans retain their own authority.
struct ClientUpdateRequirementStore {
    enum Scope: String, CaseIterable {
        case identification
        case history
    }

    let defaults: UserDefaults

    func blockedBuild(for scope: Scope, accountID: UUID) -> String? {
        defaults.dictionary(forKey: key(accountID))?[scope.rawValue] as? String
    }

    func record(_ scope: Scope, accountID: UUID, build: String) {
        var values = defaults.dictionary(forKey: key(accountID)) ?? [:]
        values[scope.rawValue] = build
        defaults.set(values, forKey: key(accountID))
    }

    func clear(_ scope: Scope, accountID: UUID) {
        var values = defaults.dictionary(forKey: key(accountID)) ?? [:]
        values.removeValue(forKey: scope.rawValue)
        if values.isEmpty {
            defaults.removeObject(forKey: key(accountID))
        } else {
            defaults.set(values, forKey: key(accountID))
        }
    }

    private func key(_ accountID: UUID) -> String {
        UserDefaultsKeys.clientUpdateRequirementPrefix + accountID.uuidString.lowercased()
    }
}
