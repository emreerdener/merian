import Foundation

struct SpeciesPreferredNameSyncDiagnostics: Equatable, Sendable {
    enum Status: String, Equatable, Sendable {
        case running
        case success
        case failure
        case skipped
    }

    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let status: Status?
    let message: String?
    let lastPushedCount: Int
    let lastPulledCount: Int
}

enum SpeciesPreferredNameStore {
    private static func key(for scientificName: String) -> String {
        UserDefaultsKeys.speciesPreferredNamePrefix + scientificName
    }

    static func legacyPreferences(userDefaults: UserDefaults = .standard) -> [String: String] {
        let prefix = UserDefaultsKeys.speciesPreferredNamePrefix
        var preferences: [String: String] = [:]

        for (key, value) in userDefaults.dictionaryRepresentation()
        where key.hasPrefix(prefix) {
            let scientificName = String(key.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preferredName = (value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !scientificName.isEmpty, let preferredName, !preferredName.isEmpty else {
                continue
            }

            preferences[scientificName] = preferredName
        }

        return preferences
    }

    static func preferredName(for scientificName: String, userDefaults: UserDefaults = .standard) -> String? {
        guard !scientificName.isEmpty else { return nil }
        let value = userDefaults.string(forKey: key(for: scientificName))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setPreferredName(_ name: String?, for scientificName: String, userDefaults: UserDefaults = .standard) {
        guard !scientificName.isEmpty else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, trimmed?.isEmpty == false {
            userDefaults.set(name, forKey: key(for: scientificName))
        } else {
            userDefaults.removeObject(forKey: key(for: scientificName))
        }
    }

    static func clearPreferredName(for scientificName: String, userDefaults: UserDefaults = .standard) {
        setPreferredName(nil, for: scientificName, userDefaults: userDefaults)
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.speciesPreferredNamePrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func clearAllAccountData(
        userDefaults: UserDefaults = .standard
    ) {
        clearAll(userDefaults: userDefaults)
        userDefaults.removeObject(
            forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes
        )
        clearSyncDiagnostics(userDefaults: userDefaults)
    }

    static func hasStoredAccountData(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        if userDefaults.dictionaryRepresentation().keys.contains(where: {
            $0.hasPrefix(UserDefaultsKeys.speciesPreferredNamePrefix)
        }) {
            return true
        }

        return [
            UserDefaultsKeys.pendingSpeciesPreferredNameDeletes,
            UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt,
            UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt,
            UserDefaultsKeys.speciesPreferredNameSyncStatus,
            UserDefaultsKeys.speciesPreferredNameSyncMessage,
            UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount,
            UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount
        ].contains { userDefaults.object(forKey: $0) != nil }
    }

    static func pendingDeleteDates(userDefaults: UserDefaults = .standard) -> [String: Date] {
        let rawValue = userDefaults.dictionary(forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes) ?? [:]
        var datesByScientificName: [String: Date] = [:]

        for (scientificName, value) in rawValue {
            let normalizedName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else { continue }

            if let timestamp = value as? Double {
                datesByScientificName[normalizedName] = Date(timeIntervalSince1970: timestamp)
            } else if let date = value as? Date {
                datesByScientificName[normalizedName] = date
            }
        }

        return datesByScientificName
    }

    static func markPendingCloudDelete(
        for scientificName: String,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        let scientificName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scientificName.isEmpty else { return }

        var rawValue = pendingDeleteDates(userDefaults: userDefaults)
            .mapValues(\.timeIntervalSince1970)
        rawValue[scientificName] = date.timeIntervalSince1970
        userDefaults.set(rawValue, forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes)
    }

    static func clearPendingCloudDelete(
        for scientificName: String,
        userDefaults: UserDefaults = .standard
    ) {
        let scientificName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scientificName.isEmpty else { return }

        var rawValue = pendingDeleteDates(userDefaults: userDefaults)
            .mapValues(\.timeIntervalSince1970)
        rawValue.removeValue(forKey: scientificName)

        if rawValue.isEmpty {
            userDefaults.removeObject(forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes)
        } else {
            userDefaults.set(rawValue, forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes)
        }
    }

    static func syncDiagnostics(userDefaults: UserDefaults = .standard) -> SpeciesPreferredNameSyncDiagnostics {
        let status = userDefaults.string(forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus)
            .flatMap(SpeciesPreferredNameSyncDiagnostics.Status.init(rawValue:))

        return SpeciesPreferredNameSyncDiagnostics(
            lastAttemptAt: userDefaults.object(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt) as? Date,
            lastSuccessAt: userDefaults.object(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt) as? Date,
            status: status,
            message: userDefaults.string(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage),
            lastPushedCount: userDefaults.integer(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount),
            lastPulledCount: userDefaults.integer(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount)
        )
    }

    static func recordSyncAttempt(at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.running.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
    }

    static func recordSyncSuccess(
        at date: Date = Date(),
        pushedCount: Int,
        pulledCount: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.success.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
        userDefaults.set(max(0, pushedCount), forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount)
        userDefaults.set(max(0, pulledCount), forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount)
    }

    static func recordSyncFailure(
        _ message: String,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.failure.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.set(normalizedDiagnosticMessage(message), forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
    }

    static func recordSyncSkip(
        _ reason: String,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.skipped.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.set(normalizedDiagnosticMessage(reason), forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
    }

    static func clearSyncDiagnostics(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount)
    }

    private static func normalizedDiagnosticMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown sync outcome." : trimmed
    }
}
