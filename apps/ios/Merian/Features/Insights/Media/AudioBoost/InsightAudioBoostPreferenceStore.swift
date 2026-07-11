import Foundation

struct InsightAudioBoostPreferenceStore {
    private struct Entry: Codable {
        let scanId: String
        var lastAccessedAt: Date
    }

    private let defaults: UserDefaults
    private let key: String
    private let now: () -> Date
    private let maxEntries = 500
    private let retentionInterval: TimeInterval = 180 * 24 * 60 * 60

    init(
        defaults: UserDefaults = .standard,
        key: String = "InsightAudioBoostEnabledScansV1",
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    func isEnabled(for scanId: String) -> Bool {
        var entries = loadPrunedEntries()
        guard let index = entries.firstIndex(where: { $0.scanId == scanId }) else { return false }
        entries[index].lastAccessedAt = now()
        save(entries)
        return true
    }

    func setEnabled(_ enabled: Bool, for scanId: String) {
        var entries = loadPrunedEntries().filter { $0.scanId != scanId }
        if enabled {
            entries.append(Entry(scanId: scanId, lastAccessedAt: now()))
        }
        save(Array(entries.sorted { $0.lastAccessedAt > $1.lastAccessedAt }.prefix(maxEntries)))
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

enum InsightAudioBoostAvailability {
    static func isAvailable(
        hasPersistedScan: Bool,
        isProcessing: Bool,
        hasStandaloneAudio: Bool
    ) -> Bool {
        hasPersistedScan && !isProcessing && hasStandaloneAudio
    }
}
