import Foundation
import SwiftData

/// Repairs the non-atomic boundary between SwiftData preference mutations and
/// their UserDefaults tombstone markers before cloud reconciliation is planned.
@MainActor
enum SpeciesPreferenceLocalRecovery {
    static func requireWithinLimit(
        localPreferences: [UserSpeciesPreference],
        remoteScientificNames: Set<String>,
        pendingDeletes: [String: Date],
        maximumCount: Int
    ) throws {
        let localScientificNames = Set(
            localPreferences.compactMap { preference in
                normalizedScientificName(preference.scientificName)
            }
        )
        let pendingDeleteScientificNames = Set(
            pendingDeletes.keys.compactMap(normalizedScientificName)
        )
        guard localScientificNames
            .union(remoteScientificNames)
            .union(pendingDeleteScientificNames).count <= maximumCount else {
            throw SpeciesPreferenceCloudSyncError.preferenceLimitExceeded(
                limit: maximumCount
            )
        }
    }

    /// Equal timestamps retain the active value, matching the feature's
    /// conflict policy.
    static func recover(
        localPreferences: [UserSpeciesPreference],
        pendingDeletes: inout [String: Date],
        ownerUserID: UUID,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) throws -> [UserSpeciesPreference] {
        var activePreferences: [UserSpeciesPreference] = []
        activePreferences.reserveCapacity(localPreferences.count)
        var stalePendingDeletes: [String: Date] = [:]
        var deletedLocalPreference = false

        for preference in localPreferences {
            let scientificName = SpeciesPreferredNamePolicy
                .normalizedScientificName(preference.scientificName)
            guard let deletedAt = pendingDeletes[scientificName] else {
                activePreferences.append(preference)
                continue
            }

            let hasValidActiveValue = SpeciesPreferredNamePolicy
                .normalizedPreferredName(preference.preferredCommonName) != nil
            if hasValidActiveValue, preference.updatedAt >= deletedAt {
                pendingDeletes.removeValue(forKey: scientificName)
                stalePendingDeletes[scientificName] = deletedAt
                activePreferences.append(preference)
            } else {
                modelContext.delete(preference)
                deletedLocalPreference = true
            }
        }

        if deletedLocalPreference {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "Failed to recover interrupted species preference mutation: \(error.localizedDescription, privacy: .private)"
                )
                throw error
            }
        }

        for (scientificName, deletedAt) in stalePendingDeletes {
            SpeciesPreferredNameStore.clearPendingCloudDelete(
                for: scientificName,
                ownerUserID: ownerUserID,
                ifNotNewerThan: deletedAt,
                userDefaults: legacyDefaults
            )
        }
        return activePreferences
    }

    private static func normalizedScientificName(_ value: String) -> String? {
        let normalized = SpeciesPreferredNamePolicy.normalizedScientificName(
            value
        )
        return normalized.isEmpty ? nil : normalized
    }
}
