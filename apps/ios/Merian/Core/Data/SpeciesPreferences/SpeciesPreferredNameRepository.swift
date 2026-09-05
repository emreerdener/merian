import Foundation
import SwiftData

/// Account-scoped SwiftData source of truth for preferred species names.
///
/// Every operation requires the authenticated account id. Cloud reconciliation
/// is delegated to `SpeciesPreferredNameCloudSyncCoordinator`, keeping network
/// and Auth singleton resolution out of this repository.
@MainActor
enum SpeciesPreferredNameRepository {
    static func preferredName(
        for scientificName: String,
        ownerUserID: UUID,
        modelContext: ModelContext
    ) -> String? {
        let scientificName = SpeciesPreferredNamePolicy
            .normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return nil }

        do {
            guard let record = try fetchPreference(
                for: scientificName,
                ownerUserID: ownerUserID,
                modelContext: modelContext
            ) else {
                return nil
            }
            return SpeciesPreferredNamePolicy.normalizedPreferredName(
                record.preferredCommonName
            )
        } catch {
            MerianLog.data.error(
                "Failed to fetch account species preferred name: \(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }

    static func preferredNames(
        for scientificNames: [String],
        ownerUserID: UUID,
        modelContext: ModelContext
    ) -> [String: String] {
        let normalizedNames = Array(
            Set(
                scientificNames
                    .map(
                        SpeciesPreferredNamePolicy.normalizedScientificName
                    )
                    .filter { !$0.isEmpty }
            )
        ).sorted()

        let maximumCount = SpeciesPreferredNameResourceLimits
            .maximumLocalPreferenceCount
        if normalizedNames.count > maximumCount {
            MerianLog.data.error(
                "Truncating species preferred-name batch from \(normalizedNames.count, privacy: .public) to \(maximumCount, privacy: .public)"
            )
        }

        let boundedNames = Array(normalizedNames.prefix(maximumCount))
        do {
            let records = try fetchPreferences(
                for: boundedNames,
                ownerUserID: ownerUserID,
                modelContext: modelContext
            )
            return records.compactMapValues { record in
                SpeciesPreferredNamePolicy.normalizedPreferredName(
                    record.preferredCommonName
                )
            }
        } catch {
            MerianLog.data.error(
                "Failed to batch fetch account species preferred names: \(error.localizedDescription, privacy: .private)"
            )
            return [:]
        }
    }

    /// Removes device-global V50/UserDefaults residue without assigning it to
    /// the first account that launches the upgraded app.
    @discardableResult
    static func discardLegacyUnscopedPreferences(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> SpeciesNameMigrationResult {
        let legacyCount = SpeciesPreferredNameStore.legacyPreferences(
            userDefaults: legacyDefaults
        ).count

        do {
            let unowned = try modelContext.fetch(
                FetchDescriptor<UserSpeciesPreference>(
                    predicate: #Predicate { $0.ownerUserId == "" }
                )
            )
            unowned.forEach(modelContext.delete)
            if !unowned.isEmpty {
                try modelContext.save()
            }
            SpeciesPreferredNameStore.discardLegacyUnscopedData(
                userDefaults: legacyDefaults
            )
            return SpeciesNameMigrationResult(
                scannedCount: legacyCount + unowned.count,
                promotedCount: 0,
                preservedExistingCount: 0,
                removedLegacyCount: legacyCount + unowned.count,
                failedCount: 0
            )
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "Failed to discard unscoped species preferences: \(error.localizedDescription, privacy: .private)"
            )
            return SpeciesNameMigrationResult(
                scannedCount: legacyCount,
                promotedCount: 0,
                preservedExistingCount: 0,
                removedLegacyCount: 0,
                failedCount: legacyCount
            )
        }
    }

    @discardableResult
    static func setPreferredName(
        _ name: String?,
        for scientificName: String,
        ownerUserID: UUID,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        let scientificName = SpeciesPreferredNamePolicy
            .normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        let trimmedName = name?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let preferredName = SpeciesPreferredNamePolicy
            .normalizedPreferredName(name)
        if trimmedName?.isEmpty == false, preferredName == nil {
            return false
        }
        guard let preferredName else {
            return clearPreferredName(
                for: scientificName,
                ownerUserID: ownerUserID,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
        }

        do {
            if let existing = try fetchPreference(
                for: scientificName,
                ownerUserID: ownerUserID,
                modelContext: modelContext
            ) {
                existing.preferredCommonName = preferredName
                existing.updatedAt = Date()
            } else {
                guard try preferenceCount(
                    ownerUserID: ownerUserID,
                    modelContext: modelContext
                ) < SpeciesPreferredNameResourceLimits
                    .maximumLocalPreferenceCount else {
                    MerianLog.data.error(
                        "Rejected species preferred name at the local account limit."
                    )
                    return false
                }
                modelContext.insert(
                    UserSpeciesPreference(
                        ownerUserID: ownerUserID,
                        scientificName: scientificName,
                        preferredCommonName: preferredName
                    )
                )
            }

            try modelContext.save()
            SpeciesPreferredNameStore.clearPendingCloudDelete(
                for: scientificName,
                ownerUserID: ownerUserID,
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
                "Failed to save account species preferred name: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    @discardableResult
    static func clearPreferredName(
        for scientificName: String,
        ownerUserID: UUID,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        let scientificName = SpeciesPreferredNamePolicy
            .normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        do {
            if let existing = try fetchPreference(
                for: scientificName,
                ownerUserID: ownerUserID,
                modelContext: modelContext
            ) {
                modelContext.delete(existing)
                try modelContext.save()
            }
            SpeciesPreferredNameStore.markPendingCloudDelete(
                for: scientificName,
                ownerUserID: ownerUserID,
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
                "Failed to clear account species preferred name: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private static func fetchPreference(
        for scientificName: String,
        ownerUserID: UUID,
        modelContext: ModelContext
    ) throws -> UserSpeciesPreference? {
        let targetID = UserSpeciesPreference.identifier(
            ownerUserID: ownerUserID,
            scientificName: scientificName
        )
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func fetchPreferences(
        for scientificNames: [String],
        ownerUserID: UUID,
        modelContext: ModelContext
    ) throws -> [String: UserSpeciesPreference] {
        guard !scientificNames.isEmpty else { return [:] }

        let ownerID = ownerUserID.uuidString.lowercased()
        let targetScientificNames = scientificNames
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate {
                $0.ownerUserId == ownerID
                    && targetScientificNames.contains($0.scientificName)
            }
        )
        descriptor.fetchLimit = targetScientificNames.count

        return Dictionary(
            uniqueKeysWithValues: try modelContext.fetch(descriptor).map {
                ($0.scientificName, $0)
            }
        )
    }

    private static func preferenceCount(
        ownerUserID: UUID,
        modelContext: ModelContext
    ) throws -> Int {
        let ownerID = ownerUserID.uuidString.lowercased()
        let descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate { $0.ownerUserId == ownerID }
        )
        return try modelContext.fetchCount(descriptor)
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
