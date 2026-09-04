import Foundation

enum ExploreShareStateStore {
    private static func key(for scanId: String) -> String {
        UserDefaultsKeys.sharedExplorePostIdPrefix + scanId
    }

    static func sharedPostId(for scanId: String, userDefaults: UserDefaults = .standard) -> String? {
        let value = userDefaults.string(forKey: key(for: scanId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setSharedPostId(_ postId: String?, for scanId: String, userDefaults: UserDefaults = .standard) {
        let trimmed = postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            userDefaults.set(trimmed, forKey: key(for: scanId))
        } else {
            userDefaults.removeObject(forKey: key(for: scanId))
        }
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.sharedExplorePostIdPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func hasStoredValues(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(UserDefaultsKeys.sharedExplorePostIdPrefix)
        }
    }
}
