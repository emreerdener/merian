import Foundation

enum ExploreMediaOverviewPreferences {
    static func dismissedSignature(
        ownerUserID: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let key = preferenceKey(ownerUserID: ownerUserID) else { return nil }
        return defaults.string(forKey: key)
    }

    static func dismiss(
        signature: String,
        ownerUserID: String,
        defaults: UserDefaults = .standard
    ) {
        guard !signature.isEmpty,
              let key = preferenceKey(ownerUserID: ownerUserID) else { return }
        defaults.set(signature, forKey: key)
    }

    static func clear(
        ownerUserID: String,
        defaults: UserDefaults = .standard
    ) {
        guard let key = preferenceKey(ownerUserID: ownerUserID) else { return }
        defaults.removeObject(forKey: key)
    }

    private static func preferenceKey(ownerUserID: String) -> String? {
        let normalizedOwnerUserID = ownerUserID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedOwnerUserID.isEmpty else { return nil }
        return UserDefaultsKeys.dismissedUnavailableMediaOverviewSignaturePrefix
            + normalizedOwnerUserID
    }
}
