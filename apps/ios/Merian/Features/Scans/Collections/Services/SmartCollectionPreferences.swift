import Foundation

enum SmartCollectionPreferences {
    private static let nonHideableIDs: Set<String> = ["needs review"]

    static func hiddenIDs(
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        Set(
            defaults.stringArray(
                forKey: UserDefaultsKeys.hiddenSmartCollectionIDs
            ) ?? []
        )
        .subtracting(nonHideableIDs)
    }

    @discardableResult
    static func hide(
        id: String,
        defaults: UserDefaults = .standard
    ) -> Set<String> {
        var ids = hiddenIDs(defaults: defaults)
        guard !nonHideableIDs.contains(id) else {
            persistHiddenIDs(ids, defaults: defaults)
            return ids
        }
        ids.insert(id)
        persistHiddenIDs(ids, defaults: defaults)
        return ids
    }

    static func clearHiddenIDs(defaults: UserDefaults = .standard) {
        defaults.removeObject(
            forKey: UserDefaultsKeys.hiddenSmartCollectionIDs
        )
    }

    private static func persistHiddenIDs(
        _ ids: Set<String>,
        defaults: UserDefaults
    ) {
        defaults.set(
            ids.sorted(),
            forKey: UserDefaultsKeys.hiddenSmartCollectionIDs
        )
    }
}
