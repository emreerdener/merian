import Foundation
import SwiftData

/// SwiftData source of truth for the user's preferred species display names.
///
/// Legacy `UserDefaults` values are migration input only. Cloud reconciliation
/// is delegated to `SpeciesPreferredNameCloudSyncCoordinator` so local data
/// access does not resolve a network singleton.
@MainActor
enum SpeciesPreferredNameRepository {
    static func preferredName(
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> String? {
        let scientificName = SpeciesPreferredNamePolicy
            .normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return nil }

        let record: UserSpeciesPreference?
        do {
            record = try fetchPreference(
                for: scientificName,
                modelContext: modelContext
            )
        } catch {
            MerianLog.data.error(
                "Failed to fetch species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }

        if let record {
            let preferredName = SpeciesPreferredNamePolicy
                .normalizedPreferredName(record.preferredCommonName)
            if let preferredName {
                SpeciesPreferredNameStore.clearPreferredName(
                    for: scientificName,
                    userDefaults: legacyDefaults
                )
                return preferredName
            }
        }

        guard let legacyName = SpeciesPreferredNameStore.preferredName(
            for: scientificName,
            userDefaults: legacyDefaults
        ) else {
            return nil
        }

        _ = setPreferredName(
            legacyName,
            for: scientificName,
            modelContext: modelContext,
            legacyDefaults: legacyDefaults
        )
        return legacyName
    }

    static func preferredNames(
        for scientificNames: [String],
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> [String: String] {
        let normalizedNames = Array(
            Set(
                scientificNames
                    .map(
                        SpeciesPreferredNamePolicy.normalizedScientificName
                    )
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()

        let maximumCount = SpeciesPreferredNameResourceLimits
            .maximumLocalPreferenceCount
        if normalizedNames.count > maximumCount {
            MerianLog.data.error(
                "Truncating species preferred-name batch from \(normalizedNames.count, privacy: .public) to \(maximumCount, privacy: .public)"
            )
        }

        var namesByScientificName: [String: String] = [:]
        let boundedNames = Array(normalizedNames.prefix(maximumCount))
        let recordsByScientificName: [String: UserSpeciesPreference]
        do {
            recordsByScientificName = try fetchPreferences(
                for: boundedNames,
                modelContext: modelContext
            )
        } catch {
            MerianLog.data.error(
                "Failed to batch fetch species preferred names: \(error.localizedDescription, privacy: .private)"
            )
            return [:]
        }
        namesByScientificName.reserveCapacity(boundedNames.count)

        for scientificName in boundedNames {
            if let record = recordsByScientificName[scientificName],
               let preferredName = SpeciesPreferredNamePolicy
                .normalizedPreferredName(record.preferredCommonName) {
                SpeciesPreferredNameStore.clearPreferredName(
                    for: scientificName,
                    userDefaults: legacyDefaults
                )
                namesByScientificName[scientificName] = preferredName
                continue
            }

            guard let legacyName = SpeciesPreferredNameStore.preferredName(
                for: scientificName,
                userDefaults: legacyDefaults
            ) else {
                continue
            }

            _ = setPreferredName(
                legacyName,
                for: scientificName,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            namesByScientificName[scientificName] = legacyName
        }

        return namesByScientificName
    }

    @discardableResult
    static func migrateLegacyPreferences(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> SpeciesNameMigrationResult {
        let legacyPreferences = SpeciesPreferredNameStore.legacyPreferences(
            userDefaults: legacyDefaults
        )
        guard !legacyPreferences.isEmpty else {
            return SpeciesNameMigrationResult(
                scannedCount: 0,
                promotedCount: 0,
                preservedExistingCount: 0,
                removedLegacyCount: 0,
                failedCount: 0
            )
        }

        let scientificNames = legacyPreferences.keys.sorted()
        let recordsByScientificName: [String: UserSpeciesPreference]
        do {
            recordsByScientificName = try fetchPreferences(
                for: scientificNames,
                modelContext: modelContext
            )
        } catch {
            MerianLog.data.error(
                "Failed to fetch existing species preferred names during migration: \(error.localizedDescription, privacy: .private)"
            )
            return SpeciesNameMigrationResult(
                scannedCount: scientificNames.count,
                promotedCount: 0,
                preservedExistingCount: 0,
                removedLegacyCount: 0,
                failedCount: scientificNames.count
            )
        }

        var didMutateSwiftData = false
        var pendingPromotedCount = 0
        var preservedExistingCount = 0

        for scientificName in scientificNames {
            guard let legacyName = SpeciesPreferredNamePolicy
                .normalizedPreferredName(legacyPreferences[scientificName])
            else {
                continue
            }

            if let existing = recordsByScientificName[scientificName],
               SpeciesPreferredNamePolicy.normalizedPreferredName(
                   existing.preferredCommonName
               ) != nil {
                preservedExistingCount += 1
                continue
            }

            if let existing = recordsByScientificName[scientificName] {
                existing.preferredCommonName = legacyName
                existing.updatedAt = Date()
            } else {
                modelContext.insert(
                    UserSpeciesPreference(
                        scientificName: scientificName,
                        preferredCommonName: legacyName
                    )
                )
            }
            didMutateSwiftData = true
            pendingPromotedCount += 1
        }

        do {
            if didMutateSwiftData {
                try modelContext.save()
            }

            for scientificName in scientificNames {
                SpeciesPreferredNameStore.clearPreferredName(
                    for: scientificName,
                    userDefaults: legacyDefaults
                )
            }

            if pendingPromotedCount > 0 || preservedExistingCount > 0 {
                MerianLog.data.debug(
                    "Migrated \(pendingPromotedCount, privacy: .public) legacy species preferred names and removed \(scientificNames.count, privacy: .public) legacy keys."
                )
            }

            return SpeciesNameMigrationResult(
                scannedCount: scientificNames.count,
                promotedCount: pendingPromotedCount,
                preservedExistingCount: preservedExistingCount,
                removedLegacyCount: scientificNames.count,
                failedCount: 0
            )
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "Failed to migrate legacy species preferred names: \(error.localizedDescription, privacy: .private)"
            )
            return SpeciesNameMigrationResult(
                scannedCount: scientificNames.count,
                promotedCount: 0,
                preservedExistingCount: 0,
                removedLegacyCount: 0,
                failedCount: scientificNames.count
            )
        }
    }

    @discardableResult
    static func setPreferredName(
        _ name: String?,
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        let scientificName = SpeciesPreferredNamePolicy
            .normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        guard let preferredName = SpeciesPreferredNamePolicy
            .normalizedPreferredName(name) else {
            return clearPreferredName(
                for: scientificName,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
        }

        do {
            if let existing = try fetchPreference(
                for: scientificName,
                modelContext: modelContext
            ) {
                existing.preferredCommonName = preferredName
                existing.updatedAt = Date()
            } else {
                modelContext.insert(
                    UserSpeciesPreference(
                        scientificName: scientificName,
                        preferredCommonName: preferredName
                    )
                )
            }

            try modelContext.save()
            SpeciesPreferredNameStore.clearPreferredName(
                for: scientificName,
                userDefaults: legacyDefaults
            )
            SpeciesPreferredNameStore.clearPendingCloudDelete(
                for: scientificName,
                userDefaults: legacyDefaults
            )
            scheduleCloudSync(
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "Failed to save species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    @discardableResult
    static func clearPreferredName(
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        let scientificName = SpeciesPreferredNamePolicy
            .normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        do {
            if let existing = try fetchPreference(
                for: scientificName,
                modelContext: modelContext
            ) {
                modelContext.delete(existing)
                try modelContext.save()
            }

            SpeciesPreferredNameStore.clearPreferredName(
                for: scientificName,
                userDefaults: legacyDefaults
            )
            SpeciesPreferredNameStore.markPendingCloudDelete(
                for: scientificName,
                userDefaults: legacyDefaults
            )
            scheduleCloudSync(
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "Failed to clear species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private static func fetchPreference(
        for scientificName: String,
        modelContext: ModelContext
    ) throws -> UserSpeciesPreference? {
        let targetScientificName = scientificName
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate<UserSpeciesPreference> {
                $0.scientificName == targetScientificName
            }
        )
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).first
    }

    private static func fetchPreferences(
        for scientificNames: [String],
        modelContext: ModelContext
    ) throws -> [String: UserSpeciesPreference] {
        guard !scientificNames.isEmpty else { return [:] }

        let targetScientificNames = scientificNames
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate<UserSpeciesPreference> {
                targetScientificNames.contains($0.scientificName)
            }
        )
        descriptor.fetchLimit = targetScientificNames.count

        let records = try modelContext.fetch(descriptor)
        var recordsByScientificName: [String: UserSpeciesPreference] = [:]
        recordsByScientificName.reserveCapacity(records.count)
        for record in records
        where recordsByScientificName[record.scientificName] == nil {
            recordsByScientificName[record.scientificName] = record
        }
        return recordsByScientificName
    }

    private static func scheduleCloudSync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        Task { @MainActor in
            await syncCloudPreferences(
                modelContext: modelContext,
                legacyDefaults: legacyDefaults,
                force: true
            )
        }
    }
}
