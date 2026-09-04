import Foundation
import SwiftData

/// Serializes species-preference reconciliation and owns its trailing-request
/// behavior. The injected client is the only network/Auth boundary.
@MainActor
final class SpeciesPreferredNameCloudSyncCoordinator {
    struct Snapshot: Equatable {
        let isSyncing: Bool
        let hasPendingRequest: Bool
    }

    private struct PendingRequest {
        let modelContext: ModelContext
        let legacyDefaults: UserDefaults
    }

    private let client: SpeciesPreferredNameCloudClient
    private let now: @MainActor () -> Date
    private let maximumLocalPreferenceCount: Int
    private let pageSize: Int
    private let cleanSyncFreshnessInterval: TimeInterval
    private var activeTask: Task<Bool, Never>?
    private var pendingRequest: PendingRequest?

    init(
        client: SpeciesPreferredNameCloudClient,
        now: @escaping @MainActor () -> Date = { Date() },
        maximumLocalPreferenceCount: Int = SpeciesPreferredNameResourceLimits
            .maximumLocalPreferenceCount,
        pageSize: Int = SpeciesPreferredNameResourceLimits.cloudSyncPageSize,
        cleanSyncFreshnessInterval: TimeInterval =
            SpeciesPreferredNameResourceLimits
                .cleanCloudSyncFreshnessInterval
    ) {
        precondition(maximumLocalPreferenceCount > 0)
        precondition(pageSize > 0)
        precondition(cleanSyncFreshnessInterval >= 0)
        self.client = client
        self.now = now
        self.maximumLocalPreferenceCount = maximumLocalPreferenceCount
        self.pageSize = pageSize
        self.cleanSyncFreshnessInterval = cleanSyncFreshnessInterval
    }

    var snapshot: Snapshot {
        Snapshot(
            isSyncing: activeTask != nil,
            hasPendingRequest: pendingRequest != nil
        )
    }

    @discardableResult
    func sync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard,
        force: Bool = false
    ) async -> Bool {
        if let activeTask {
            pendingRequest = PendingRequest(
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            return await activeTask.value
        }
        guard force || !hasFreshCleanSync(legacyDefaults: legacyDefaults)
        else {
            return true
        }

        let task = Task { @MainActor [self] in
            defer {
                activeTask = nil
                pendingRequest = nil
            }

            var nextModelContext = modelContext
            var nextLegacyDefaults = legacyDefaults

            while true {
                let latestResult = await performSync(
                    modelContext: nextModelContext,
                    legacyDefaults: nextLegacyDefaults
                )

                guard let request = pendingRequest else {
                    return latestResult
                }

                nextModelContext = request.modelContext
                nextLegacyDefaults = request.legacyDefaults
                pendingRequest = nil
            }
        }
        activeTask = task
        return await task.value
    }

    private func hasFreshCleanSync(legacyDefaults: UserDefaults) -> Bool {
        guard SpeciesPreferredNameStore.pendingDeleteDates(
            userDefaults: legacyDefaults
        ).isEmpty else {
            return false
        }
        guard let lastSuccessAt = SpeciesPreferredNameStore.syncDiagnostics(
            userDefaults: legacyDefaults
        ).lastSuccessAt else {
            return false
        }
        let elapsed = now().timeIntervalSince(lastSuccessAt)
        return elapsed >= 0 && elapsed < cleanSyncFreshnessInterval
    }

    private func performSync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) async -> Bool {
        SpeciesPreferredNameStore.recordSyncAttempt(
            at: now(),
            userDefaults: legacyDefaults
        )

        guard let accountWorkLease = try? client.beginAccountWork() else {
            SpeciesPreferredNameStore.recordSyncSkip(
                "No stable authenticated Supabase session.",
                at: now(),
                userDefaults: legacyDefaults
            )
            return false
        }
        defer {
            client.finishAccountWork(accountWorkLease)
        }
        let userID = accountWorkLease.session.userID.uuidString

        do {
            let localPreferences = try canonicalLocalPreferences(
                fetchAllPreferences(modelContext: modelContext)
            )
            let pendingDeletes = SpeciesPreferredNameStore.pendingDeleteDates(
                userDefaults: legacyDefaults
            )
            let remoteRows = try await fetchRemotePreferences(
                userID: userID,
                accountWorkLease: accountWorkLease
            )
            try requireCurrentAccountWork(accountWorkLease)

            let remoteByScientificName = canonicalRemotePreferences(
                remoteRows
            )

            let activeUpserts = activeCloudUpserts(
                userID: userID,
                localPreferences: localPreferences,
                remoteByScientificName: remoteByScientificName
            )
            let deleteUpserts = pendingDeleteUpserts(
                userID: userID,
                pendingDeletes: pendingDeletes,
                remoteByScientificName: remoteByScientificName
            )
            let upserts = activeUpserts + deleteUpserts

            if !upserts.isEmpty {
                try await client.upsert(upserts)
                try requireCurrentAccountWork(accountWorkLease)

                for upsert in deleteUpserts {
                    SpeciesPreferredNameStore.clearPendingCloudDelete(
                        for: upsert.scientific_name,
                        userDefaults: legacyDefaults
                    )
                }
            }

            try requireCurrentAccountWork(accountWorkLease)
            try applyRemotePreferences(
                Array(remoteByScientificName.values),
                localPreferences: localPreferences,
                pendingDeletes: pendingDeletes,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            SpeciesPreferredNameStore.recordSyncSuccess(
                at: now(),
                pushedCount: upserts.count,
                pulledCount: remoteRows.count,
                userDefaults: legacyDefaults
            )

            MerianLog.data.debug(
                "Synced species preferred names with cloud: \(localPreferences.count, privacy: .public) local, \(remoteRows.count, privacy: .public) remote, \(upserts.count, privacy: .public) pushed."
            )
            return true
        } catch {
            SpeciesPreferredNameStore.recordSyncFailure(
                error.localizedDescription,
                at: now(),
                userDefaults: legacyDefaults
            )
            MerianLog.data.debug(
                "Species preferred-name cloud sync skipped or failed: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private func requireCurrentAccountWork(
        _ lease: AccountBoundWorkLease
    ) throws {
        guard client.isAccountWorkCurrent(lease) else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }
    }

    private func fetchAllPreferences(
        modelContext: ModelContext
    ) throws -> [UserSpeciesPreference] {
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        descriptor.fetchLimit = maximumLocalPreferenceCount

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error(
                "Failed to fetch local species preferred names for cloud sync: \(error.localizedDescription, privacy: .private)"
            )
            throw error
        }
    }

    private func canonicalLocalPreferences(
        _ preferences: [UserSpeciesPreference]
    ) -> [UserSpeciesPreference] {
        var latestByScientificName: [String: UserSpeciesPreference] = [:]
        for preference in preferences {
            let scientificName = SpeciesPreferredNamePolicy
                .normalizedScientificName(preference.scientificName)
            guard !scientificName.isEmpty else { continue }

            if let existing = latestByScientificName[scientificName],
               existing.updatedAt > preference.updatedAt {
                continue
            }
            latestByScientificName[scientificName] = preference
        }
        return latestByScientificName.values.sorted {
            $0.scientificName < $1.scientificName
        }
    }

    private func canonicalRemotePreferences(
        _ rows: [SpeciesPreferenceCloudRow]
    ) -> [String: SpeciesPreferenceCloudRow] {
        var latestByScientificName: [String: SpeciesPreferenceCloudRow] = [:]
        for row in rows {
            let scientificName = SpeciesPreferredNamePolicy
                .normalizedScientificName(row.scientific_name)
            guard !scientificName.isEmpty else { continue }

            guard let existing = latestByScientificName[scientificName] else {
                latestByScientificName[scientificName] = row
                continue
            }

            let existingDate = SpeciesPreferredNamePolicy.cloudDate(
                existing.updated_at
            )
            let candidateDate = SpeciesPreferredNamePolicy.cloudDate(
                row.updated_at
            )
            if existingDate == nil {
                latestByScientificName[scientificName] = row
            } else if let existingDate, let candidateDate,
                      candidateDate >= existingDate {
                latestByScientificName[scientificName] = row
            }
        }
        return latestByScientificName
    }

    private func fetchRemotePreferences(
        userID: String,
        accountWorkLease: AccountBoundWorkLease
    ) async throws -> [SpeciesPreferenceCloudRow] {
        var rows: [SpeciesPreferenceCloudRow] = []
        rows.reserveCapacity(pageSize)

        var offset = 0
        while true {
            let page = try await client.fetchPage(
                userID: userID,
                offset: offset,
                pageSize: pageSize
            )
            try requireCurrentAccountWork(accountWorkLease)

            rows.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        return rows
    }

    private func activeCloudUpserts(
        userID: String,
        localPreferences: [UserSpeciesPreference],
        remoteByScientificName: [String: SpeciesPreferenceCloudRow]
    ) -> [SpeciesPreferenceCloudUpsert] {
        localPreferences.compactMap { preference in
            let scientificName = SpeciesPreferredNamePolicy
                .normalizedScientificName(preference.scientificName)
            guard !scientificName.isEmpty,
                  let preferredName = SpeciesPreferredNamePolicy
                    .normalizedPreferredName(
                        preference.preferredCommonName
                    ) else {
                return nil
            }

            if !SpeciesPreferredNamePolicy.needsActiveCloudUpsert(
                preferredName: preferredName,
                updatedAt: preference.updatedAt,
                remote: remoteByScientificName[scientificName]
            ) {
                return nil
            }

            return SpeciesPreferenceCloudUpsert(
                user_id: userID,
                scientific_name: scientificName,
                preferred_common_name: preferredName,
                deleted_at: nil
            )
        }
    }

    private func pendingDeleteUpserts(
        userID: String,
        pendingDeletes: [String: Date],
        remoteByScientificName: [String: SpeciesPreferenceCloudRow]
    ) -> [SpeciesPreferenceCloudUpsert] {
        pendingDeletes.compactMap { scientificName, deletedAt in
            let scientificName = SpeciesPreferredNamePolicy
                .normalizedScientificName(scientificName)
            guard !scientificName.isEmpty else { return nil }

            if !SpeciesPreferredNamePolicy.needsPendingDeleteCloudUpsert(
                deletedAt: deletedAt,
                remote: remoteByScientificName[scientificName]
            ) {
                return nil
            }

            return SpeciesPreferenceCloudUpsert(
                user_id: userID,
                scientific_name: scientificName,
                preferred_common_name: nil,
                deleted_at: SpeciesPreferredNamePolicy.cloudString(deletedAt)
            )
        }
    }

    private func applyRemotePreferences(
        _ remoteRows: [SpeciesPreferenceCloudRow],
        localPreferences: [UserSpeciesPreference],
        pendingDeletes: [String: Date],
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) throws {
        guard !remoteRows.isEmpty else { return }

        var localByScientificName: [String: UserSpeciesPreference] = [:]
        for preference in localPreferences {
            let scientificName = SpeciesPreferredNamePolicy
                .normalizedScientificName(preference.scientificName)
            guard !scientificName.isEmpty else { continue }
            localByScientificName[scientificName] = preference
        }
        var didMutate = false
        var legacyNamesToClear: Set<String> = []
        var pendingDeletesToClear: Set<String> = []

        for remote in remoteRows {
            let scientificName = SpeciesPreferredNamePolicy
                .normalizedScientificName(remote.scientific_name)
            guard !scientificName.isEmpty,
                  let remoteUpdatedAt = SpeciesPreferredNamePolicy.cloudDate(
                      remote.updated_at
                  ) else {
                continue
            }

            if remote.deleted_at != nil {
                if let localPreference =
                    localByScientificName[scientificName],
                    remoteUpdatedAt > localPreference.updatedAt {
                    modelContext.delete(localPreference)
                    localByScientificName.removeValue(
                        forKey: scientificName
                    )
                    legacyNamesToClear.insert(scientificName)
                    didMutate = true
                }
                pendingDeletesToClear.insert(scientificName)
                continue
            }

            if let pendingDelete = pendingDeletes[scientificName],
               pendingDelete >= remoteUpdatedAt {
                continue
            }

            guard let remotePreferredName = SpeciesPreferredNamePolicy
                .normalizedPreferredName(remote.preferred_common_name) else {
                continue
            }

            if let localPreference = localByScientificName[scientificName] {
                if SpeciesPreferredNamePolicy.normalizedPreferredName(
                    localPreference.preferredCommonName
                ) == remotePreferredName {
                    legacyNamesToClear.insert(scientificName)
                    pendingDeletesToClear.insert(scientificName)
                    continue
                }
                guard remoteUpdatedAt > localPreference.updatedAt else {
                    continue
                }
                localPreference.preferredCommonName = remotePreferredName
                localPreference.updatedAt = remoteUpdatedAt
            } else {
                let preference = UserSpeciesPreference(
                    scientificName: scientificName,
                    preferredCommonName: remotePreferredName,
                    updatedAt: remoteUpdatedAt
                )
                modelContext.insert(preference)
                localByScientificName[scientificName] = preference
            }
            legacyNamesToClear.insert(scientificName)
            pendingDeletesToClear.insert(scientificName)
            didMutate = true
        }

        if didMutate {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "Failed to apply remote species preferred names: \(error.localizedDescription, privacy: .private)"
                )
                throw error
            }
        }

        for scientificName in legacyNamesToClear {
            SpeciesPreferredNameStore.clearPreferredName(
                for: scientificName,
                userDefaults: legacyDefaults
            )
        }
        for scientificName in pendingDeletesToClear {
            SpeciesPreferredNameStore.clearPendingCloudDelete(
                for: scientificName,
                userDefaults: legacyDefaults
            )
        }
    }
}

@MainActor
private enum SpeciesPreferredNameLiveCloudSync {
    static let coordinator = SpeciesPreferredNameCloudSyncCoordinator(
        client: .live
    )
}

extension SpeciesPreferredNameRepository {
    @discardableResult
    static func syncCloudPreferences(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard,
        force: Bool = false
    ) async -> Bool {
        guard !TestExecutionCoordinator.isRunningTests else { return false }
        return await SpeciesPreferredNameLiveCloudSync.coordinator.sync(
            modelContext: modelContext,
            legacyDefaults: legacyDefaults,
            force: force
        )
    }
}
