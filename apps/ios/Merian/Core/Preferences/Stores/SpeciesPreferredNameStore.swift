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

/// Owns preferred-name migration residue and account-scoped sync metadata.
///
/// Preferred names themselves live in SwiftData. The old device-global name,
/// tombstone, and diagnostics keys are read only for deterministic removal;
/// they are never adopted by whichever account signs in next.
enum SpeciesPreferredNameStore {
    private static let accountScopedPrefixes = [
        UserDefaultsKeys.pendingSpeciesPreferredNameDeletesV2Prefix,
        UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAtV2Prefix,
        UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAtV2Prefix,
        UserDefaultsKeys.speciesPreferredNameSyncStatusV2Prefix,
        UserDefaultsKeys.speciesPreferredNameSyncMessageV2Prefix,
        UserDefaultsKeys.speciesPreferredNameSyncLastPushedCountV2Prefix,
        UserDefaultsKeys.speciesPreferredNameSyncLastPulledCountV2Prefix
    ]

    private static let legacySingletonKeys = [
        UserDefaultsKeys.pendingSpeciesPreferredNameDeletes,
        UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt,
        UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt,
        UserDefaultsKeys.speciesPreferredNameSyncStatus,
        UserDefaultsKeys.speciesPreferredNameSyncMessage,
        UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount,
        UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount
    ]

    private static func legacyNameKey(for scientificName: String) -> String {
        UserDefaultsKeys.speciesPreferredNamePrefix + scientificName
    }

    private static func accountKey(
        prefix: String,
        ownerUserID: UUID
    ) -> String {
        prefix + ownerUserID.uuidString.lowercased()
    }

    static func legacyPreferences(
        userDefaults: UserDefaults = .standard
    ) -> [String: String] {
        let prefix = UserDefaultsKeys.speciesPreferredNamePrefix
        var preferences: [String: String] = [:]

        for (key, value) in userDefaults.dictionaryRepresentation()
        where key.hasPrefix(prefix) {
            let scientificName = String(key.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preferredName = (value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !scientificName.isEmpty,
                  let preferredName,
                  !preferredName.isEmpty else {
                continue
            }
            preferences[scientificName] = preferredName
        }
        return preferences
    }

    static func setLegacyPreferredName(
        _ name: String?,
        for scientificName: String,
        userDefaults: UserDefaults = .standard
    ) {
        guard !scientificName.isEmpty else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = legacyNameKey(for: scientificName)
        if let name, trimmed?.isEmpty == false {
            userDefaults.set(name, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func discardLegacyUnscopedData(
        userDefaults: UserDefaults = .standard
    ) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.speciesPreferredNamePrefix) {
            userDefaults.removeObject(forKey: key)
        }
        legacySingletonKeys.forEach(userDefaults.removeObject(forKey:))
    }

    static func clearAllAccountData(
        userDefaults: UserDefaults = .standard
    ) {
        discardLegacyUnscopedData(userDefaults: userDefaults)
        for key in userDefaults.dictionaryRepresentation().keys
        where accountScopedPrefixes.contains(where: key.hasPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func hasStoredAccountData(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.dictionaryRepresentation().keys.contains { key in
            key.hasPrefix(UserDefaultsKeys.speciesPreferredNamePrefix)
                || legacySingletonKeys.contains(key)
                || accountScopedPrefixes.contains(where: key.hasPrefix)
        }
    }

    static func pendingDeleteDates(
        ownerUserID: UUID,
        userDefaults: UserDefaults = .standard
    ) -> [String: Date] {
        let rawValue = userDefaults.dictionary(
            forKey: accountKey(
                prefix: UserDefaultsKeys
                    .pendingSpeciesPreferredNameDeletesV2Prefix,
                ownerUserID: ownerUserID
            )
        ) ?? [:]
        var datesByScientificName: [String: Date] = [:]

        for (scientificName, value) in rawValue {
            let normalizedName = scientificName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalizedName.isEmpty else { continue }
            let date: Date?
            if let timestamp = value as? Double {
                date = Date(timeIntervalSince1970: timestamp)
            } else {
                date = value as? Date
            }
            guard let date,
                  datesByScientificName[normalizedName].map({ $0 >= date })
                    != true else {
                continue
            }
            datesByScientificName[normalizedName] = date
        }
        return datesByScientificName
    }

    static func markPendingCloudDelete(
        for scientificName: String,
        ownerUserID: UUID,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        let scientificName = scientificName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !scientificName.isEmpty else { return }

        var rawValue = pendingDeleteDates(
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        ).mapValues(\.timeIntervalSince1970)
        let existingTimestamp = rawValue[scientificName]
        rawValue[scientificName] = max(
            existingTimestamp ?? -Double.greatestFiniteMagnitude,
            date.timeIntervalSince1970
        )
        userDefaults.set(
            rawValue,
            forKey: accountKey(
                prefix: UserDefaultsKeys
                    .pendingSpeciesPreferredNameDeletesV2Prefix,
                ownerUserID: ownerUserID
            )
        )
    }

    static func clearPendingCloudDelete(
        for scientificName: String,
        ownerUserID: UUID,
        ifNotNewerThan capturedDate: Date? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let scientificName = scientificName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !scientificName.isEmpty else { return }

        let key = accountKey(
            prefix: UserDefaultsKeys
                .pendingSpeciesPreferredNameDeletesV2Prefix,
            ownerUserID: ownerUserID
        )
        var rawValue = pendingDeleteDates(
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        ).mapValues(\.timeIntervalSince1970)
        if let capturedDate,
           let currentTimestamp = rawValue[scientificName],
           currentTimestamp > capturedDate.timeIntervalSince1970 {
            return
        }
        rawValue.removeValue(forKey: scientificName)
        if rawValue.isEmpty {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(rawValue, forKey: key)
        }
    }

    static func syncDiagnostics(
        ownerUserID: UUID,
        userDefaults: UserDefaults = .standard
    ) -> SpeciesPreferredNameSyncDiagnostics {
        func key(_ prefix: String) -> String {
            accountKey(prefix: prefix, ownerUserID: ownerUserID)
        }
        let status = userDefaults.string(
            forKey: key(UserDefaultsKeys.speciesPreferredNameSyncStatusV2Prefix)
        ).flatMap(SpeciesPreferredNameSyncDiagnostics.Status.init(rawValue:))

        return SpeciesPreferredNameSyncDiagnostics(
            lastAttemptAt: userDefaults.object(
                forKey: key(UserDefaultsKeys
                    .speciesPreferredNameSyncLastAttemptAtV2Prefix)
            ) as? Date,
            lastSuccessAt: userDefaults.object(
                forKey: key(UserDefaultsKeys
                    .speciesPreferredNameSyncLastSuccessAtV2Prefix)
            ) as? Date,
            status: status,
            message: userDefaults.string(
                forKey: key(UserDefaultsKeys
                    .speciesPreferredNameSyncMessageV2Prefix)
            ),
            lastPushedCount: userDefaults.integer(
                forKey: key(UserDefaultsKeys
                    .speciesPreferredNameSyncLastPushedCountV2Prefix)
            ),
            lastPulledCount: userDefaults.integer(
                forKey: key(UserDefaultsKeys
                    .speciesPreferredNameSyncLastPulledCountV2Prefix)
            )
        )
    }

    static func recordSyncAttempt(
        ownerUserID: UUID,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        set(
            date,
            prefix: UserDefaultsKeys
                .speciesPreferredNameSyncLastAttemptAtV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        set(
            SpeciesPreferredNameSyncDiagnostics.Status.running.rawValue,
            prefix: UserDefaultsKeys.speciesPreferredNameSyncStatusV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        remove(
            prefix: UserDefaultsKeys.speciesPreferredNameSyncMessageV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
    }

    static func recordSyncSuccess(
        ownerUserID: UUID,
        at date: Date = Date(),
        pushedCount: Int,
        pulledCount: Int,
        userDefaults: UserDefaults = .standard
    ) {
        set(
            date,
            prefix: UserDefaultsKeys
                .speciesPreferredNameSyncLastSuccessAtV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        set(
            SpeciesPreferredNameSyncDiagnostics.Status.success.rawValue,
            prefix: UserDefaultsKeys.speciesPreferredNameSyncStatusV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        remove(
            prefix: UserDefaultsKeys.speciesPreferredNameSyncMessageV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        set(
            max(0, pushedCount),
            prefix: UserDefaultsKeys
                .speciesPreferredNameSyncLastPushedCountV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        set(
            max(0, pulledCount),
            prefix: UserDefaultsKeys
                .speciesPreferredNameSyncLastPulledCountV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
    }

    static func recordSyncFailure(
        _ message: String,
        ownerUserID: UUID,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        recordSyncOutcome(
            status: .failure,
            message: message,
            ownerUserID: ownerUserID,
            at: date,
            userDefaults: userDefaults
        )
    }

    static func recordSyncSkip(
        _ reason: String,
        ownerUserID: UUID,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        recordSyncOutcome(
            status: .skipped,
            message: reason,
            ownerUserID: ownerUserID,
            at: date,
            userDefaults: userDefaults
        )
    }

    static func clearSyncDiagnostics(
        ownerUserID: UUID,
        userDefaults: UserDefaults = .standard
    ) {
        [
            UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAtV2Prefix,
            UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAtV2Prefix,
            UserDefaultsKeys.speciesPreferredNameSyncStatusV2Prefix,
            UserDefaultsKeys.speciesPreferredNameSyncMessageV2Prefix,
            UserDefaultsKeys.speciesPreferredNameSyncLastPushedCountV2Prefix,
            UserDefaultsKeys.speciesPreferredNameSyncLastPulledCountV2Prefix
        ].forEach {
            remove(
                prefix: $0,
                ownerUserID: ownerUserID,
                userDefaults: userDefaults
            )
        }
    }

    private static func recordSyncOutcome(
        status: SpeciesPreferredNameSyncDiagnostics.Status,
        message: String,
        ownerUserID: UUID,
        at date: Date,
        userDefaults: UserDefaults
    ) {
        set(
            date,
            prefix: UserDefaultsKeys
                .speciesPreferredNameSyncLastAttemptAtV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        set(
            status.rawValue,
            prefix: UserDefaultsKeys.speciesPreferredNameSyncStatusV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
        set(
            normalizedDiagnosticMessage(message),
            prefix: UserDefaultsKeys.speciesPreferredNameSyncMessageV2Prefix,
            ownerUserID: ownerUserID,
            userDefaults: userDefaults
        )
    }

    private static func set(
        _ value: Any,
        prefix: String,
        ownerUserID: UUID,
        userDefaults: UserDefaults
    ) {
        userDefaults.set(
            value,
            forKey: accountKey(prefix: prefix, ownerUserID: ownerUserID)
        )
    }

    private static func remove(
        prefix: String,
        ownerUserID: UUID,
        userDefaults: UserDefaults
    ) {
        userDefaults.removeObject(
            forKey: accountKey(prefix: prefix, ownerUserID: ownerUserID)
        )
    }

    private static func normalizedDiagnosticMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown sync outcome." : trimmed
    }
}
