import Foundation

enum SpeciesPreferredNameResourceLimits {
    static let maximumLocalPreferenceCount = 1_000
    static let maximumPreferredNameLength = 200
    static let cloudSyncPageSize = 500
    static let cleanCloudSyncFreshnessInterval: TimeInterval = 60
}

@MainActor
enum SpeciesPreferredNamePolicy {
    static func normalizedScientificName(_ scientificName: String) -> String {
        scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedPreferredName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed,
              !trimmed.isEmpty,
              trimmed.unicodeScalars.count <= SpeciesPreferredNameResourceLimits
                .maximumPreferredNameLength else {
            return nil
        }
        return trimmed
    }

    static func cloudString(_ date: Date) -> String {
        DateUtilities.iso8601FractionalFormatter.string(from: date)
    }

    static func cloudDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return DateUtilities.iso8601FractionalFormatter.date(from: value)
            ?? DateUtilities.iso8601Formatter.date(from: value)
    }

    static func needsActiveCloudUpsert(
        preferredName: String,
        updatedAt: Date,
        remote: SpeciesPreferenceCloudRow?
    ) -> Bool {
        guard let remote else { return true }

        if remote.deleted_at == nil,
           normalizedPreferredName(remote.preferred_common_name)
            == normalizedPreferredName(preferredName) {
            return false
        }

        guard let remoteUpdatedAt = cloudDate(remote.updated_at) else {
            return true
        }
        return remoteUpdatedAt <= updatedAt
    }

    static func needsPendingDeleteCloudUpsert(
        deletedAt: Date,
        remote: SpeciesPreferenceCloudRow?
    ) -> Bool {
        guard let remote else { return true }
        if remote.deleted_at != nil { return false }
        guard let remoteUpdatedAt = cloudDate(remote.updated_at) else {
            return true
        }
        return remoteUpdatedAt <= deletedAt
    }
}

extension SpeciesPreferredNameRepository {
    static func needsActiveCloudUpsert(
        preferredName: String,
        updatedAt: Date,
        remote: SpeciesPreferenceCloudRow?
    ) -> Bool {
        SpeciesPreferredNamePolicy.needsActiveCloudUpsert(
            preferredName: preferredName,
            updatedAt: updatedAt,
            remote: remote
        )
    }

    static func needsPendingDeleteCloudUpsert(
        deletedAt: Date,
        remote: SpeciesPreferenceCloudRow?
    ) -> Bool {
        SpeciesPreferredNamePolicy.needsPendingDeleteCloudUpsert(
            deletedAt: deletedAt,
            remote: remote
        )
    }
}
