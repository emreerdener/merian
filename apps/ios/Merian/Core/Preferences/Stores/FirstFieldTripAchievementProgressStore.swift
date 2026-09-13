import Foundation

enum FirstFieldTripAchievementProgressStore {
    static func load(
        accountId: String,
        userDefaults: UserDefaults = .standard
    ) -> FirstFieldTripAchievementProgress? {
        guard let data = userDefaults.data(forKey: key(accountId: accountId)),
              let progress = try? JSONDecoder().decode(FirstFieldTripAchievementProgress.self, from: data),
              progress.awardPayload != nil else {
            return nil
        }
        return progress
    }

    static func save(
        _ progress: FirstFieldTripAchievementProgress,
        accountId: String,
        userDefaults: UserDefaults = .standard
    ) {
        guard progress.awardPayload != nil,
              let data = try? JSONEncoder().encode(progress) else { return }
        userDefaults.set(data, forKey: key(accountId: accountId))
    }

    static func key(accountId: String) -> String {
        UserDefaultsKeys.firstFieldTripAchievementProgressPrefix
            + accountId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
