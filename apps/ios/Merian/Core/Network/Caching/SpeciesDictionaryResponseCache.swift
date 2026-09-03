import Foundation

/// The two per-client response memos share mechanics, not storage or lifetime.
final class SpeciesDictionaryResponseCache {
    private let dictionary: SpeciesResponseMemo<SpeciesDictionaryEntry>
    private let observationStats: SpeciesResponseMemo<SpeciesObservationStatsEntry>

    init(now: @escaping () -> Date = Date.init) {
        dictionary = SpeciesResponseMemo(timeToLive: 10 * 60, limit: 64, now: now)
        observationStats = SpeciesResponseMemo(timeToLive: 5 * 60, limit: 64, now: now)
    }

    func dictionaryEntry(speciesId: String?, scientificName: String?) -> SpeciesDictionaryEntry? {
        dictionary.value(for: Self.primaryKey(speciesId: speciesId, scientificName: scientificName))
    }

    func storeDictionaryEntry(_ entry: SpeciesDictionaryEntry) {
        // Only the returned identity is safe to alias after stale-ID recovery.
        dictionary.insert(entry, for: Self.keys(speciesId: entry.id, scientificName: entry.scientificName))
    }

    func observationStatsEntry(speciesId: String?, scientificName: String?) -> SpeciesObservationStatsEntry? {
        observationStats.value(for: Self.primaryKey(speciesId: speciesId, scientificName: scientificName))
    }

    func storeObservationStatsEntry(
        _ entry: SpeciesObservationStatsEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) {
        let keys = Self.keys(speciesId: requestedSpeciesId, scientificName: requestedScientificName)
            .union(Self.keys(speciesId: entry.speciesId, scientificName: entry.scientificName))
        observationStats.insert(entry, for: keys)
    }

    #if DEBUG
    func resetForTesting() {
        dictionary.removeAll()
        observationStats.removeAll()
    }
    #endif

    private static func primaryKey(speciesId: String?, scientificName: String?) -> String? {
        if let speciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(speciesId) {
            return "id:\(speciesId)"
        }
        if let scientificName = SpeciesDictionaryIdentity.scientificNameCacheKey(scientificName) {
            return "name:\(scientificName)"
        }
        return nil
    }

    private static func keys(speciesId: String?, scientificName: String?) -> Set<String> {
        var keys = Set<String>()
        if let speciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(speciesId) {
            keys.insert("id:\(speciesId)")
        }
        if let scientificName = SpeciesDictionaryIdentity.scientificNameCacheKey(scientificName) {
            keys.insert("name:\(scientificName)")
        }
        return keys
    }
}

/// Private implementation detail: insertion-time TTL and capacity counted per
/// alias key. Reads do not refresh age; eviction is oldest-insertion, not LRU.
private final class SpeciesResponseMemo<Value> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    private let timeToLive: TimeInterval
    private let limit: Int
    private let now: () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    init(timeToLive: TimeInterval, limit: Int, now: @escaping () -> Date) {
        self.timeToLive = timeToLive
        self.limit = limit
        self.now = now
    }

    func value(for key: String?) -> Value? {
        guard let key else { return nil }
        lock.lock()
        defer { lock.unlock() }

        guard let cached = entries[key] else { return nil }
        guard now().timeIntervalSince(cached.storedAt) < timeToLive else {
            entries.removeValue(forKey: key)
            return nil
        }
        return cached.value
    }

    func insert(_ value: Value, for keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let storedAt = now()
        lock.lock()
        defer { lock.unlock() }

        for key in keys {
            entries[key] = Entry(value: value, storedAt: storedAt)
        }
        guard entries.count > limit else { return }

        let expiredKeys = entries
            .filter { storedAt.timeIntervalSince($0.value.storedAt) >= timeToLive }
            .map(\.key)
        for key in expiredKeys {
            entries.removeValue(forKey: key)
        }
        guard entries.count > limit else { return }

        let keysToRemove = entries
            .sorted { $0.value.storedAt < $1.value.storedAt }
            .prefix(entries.count - limit)
            .map(\.key)
        for key in keysToRemove {
            entries.removeValue(forKey: key)
        }
    }

    #if DEBUG
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
    #endif
}
