import Foundation

enum ExploreAudioBoostFeedbackPolicy {
    static func shouldPresent(actionToken: UUID?) -> Bool {
        actionToken != nil
    }
}

struct ExploreAudioBoostPreferenceStore {
    static let didChangeNotification = Notification.Name("ExploreAudioBoostPreferenceDidChange")
    static let postIdUserInfoKey = "postId"
    static let enabledUserInfoKey = "enabled"

    private struct Entry: Codable {
        let postId: String
        var lastAccessedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String
    private let now: () -> Date
    private let maxEntries = 500
    private let retentionInterval: TimeInterval = 180 * 24 * 60 * 60

    init(
        defaults: UserDefaults = .standard,
        key: String = "ExploreAudioBoostEnabledPostsV1",
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    func isEnabled(for postId: String) -> Bool {
        var entries = loadPrunedEntries()
        guard let index = entries.firstIndex(where: { $0.postId == postId }) else { return false }
        entries[index].lastAccessedAt = now()
        save(entries)
        return true
    }

    func setEnabled(_ enabled: Bool, for postId: String) {
        let currentEntries = loadPrunedEntries()
        let wasEnabled = currentEntries.contains { $0.postId == postId }
        var entries = currentEntries.filter { $0.postId != postId }
        if enabled {
            entries.append(Entry(postId: postId, lastAccessedAt: now()))
        }
        save(Array(entries.sorted { $0.lastAccessedAt > $1.lastAccessedAt }.prefix(maxEntries)))
        guard enabled != wasEnabled else { return }
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [
                Self.postIdUserInfoKey: postId,
                Self.enabledUserInfoKey: enabled
            ]
        )
    }

    private func loadPrunedEntries() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        let cutoff = now().addingTimeInterval(-retentionInterval)
        let entries = decoded.filter { $0.lastAccessedAt >= cutoff }
            .sorted { $0.lastAccessedAt > $1.lastAccessedAt }
        let pruned = Array(entries.prefix(maxEntries))
        if pruned.count != decoded.count { save(pruned) }
        return pruned
    }

    private func save(_ entries: [Entry]) {
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
