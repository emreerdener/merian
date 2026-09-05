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
        let force: Bool
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
                legacyDefaults: legacyDefaults,
                force: force || pendingRequest?.force == true
            )
            return await activeTask.value
        }

        let task = Task { @MainActor [self] in
            defer {
                activeTask = nil
                pendingRequest = nil
            }

            var nextModelContext = modelContext
            var nextLegacyDefaults = legacyDefaults
            var shouldForce = force

            while true {
                let latestResult = await performSync(
                    modelContext: nextModelContext,
                    legacyDefaults: nextLegacyDefaults,
                    force: shouldForce
                )

                guard let request = pendingRequest else {
                    return latestResult
                }

                nextModelContext = request.modelContext
                nextLegacyDefaults = request.legacyDefaults
                shouldForce = request.force
                pendingRequest = nil
            }
        }
        activeTask = task
        return await task.value
    }

    private func hasFreshCleanSync(
        ownerUserID: UUID,
        legacyDefaults: UserDefaults
    ) -> Bool {
        guard SpeciesPreferredNameStore.pendingDeleteDates(
            ownerUserID: ownerUserID,
            userDefaults: legacyDefaults
        ).isEmpty else {
            return false
        }
        let diagnostics = SpeciesPreferredNameStore.syncDiagnostics(
            ownerUserID: ownerUserID,
            userDefaults: legacyDefaults
        )
        guard diagnostics.status == .success,
              let lastSuccessAt = diagnostics.lastSuccessAt else {
            return false
        }
        let elapsed = now().timeIntervalSince(lastSuccessAt)
        return elapsed >= 0 && elapsed < cleanSyncFreshnessInterval
    }

    private func performSync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults,
        force: Bool
    ) async -> Bool {
        guard let accountWorkLease = try? client.beginAccountWork() else {
            return false
        }
        defer {
            client.finishAccountWork(accountWorkLease)
        }
        let ownerUserID = accountWorkLease.session.userID
        let userID = ownerUserID.uuidString

        guard force || !hasFreshCleanSync(
            ownerUserID: ownerUserID,
            legacyDefaults: legacyDefaults
        ) else {
            return true
        }
        SpeciesPreferredNameStore.recordSyncAttempt(
            ownerUserID: ownerUserID,
            at: now(),
            userDefaults: legacyDefaults
        )

        do {
            let remoteRows = try await fetchRemotePreferences(
                userID: userID,
                accountWorkLease: accountWorkLease
            )
            try requireCurrentAccountWork(accountWorkLease)

            var localPreferences = try canonicalLocalPreferences(
                fetchAllPreferences(
                    ownerUserID: ownerUserID,
                    modelContext: modelContext
                )
            )
            var pendingDeletes = SpeciesPreferredNameStore.pendingDeleteDates(
                ownerUserID: ownerUserID,
                userDefaults: legacyDefaults
            )

            let remoteByScientificName = canonicalRemotePreferences(
                remoteRows
            )
            try SpeciesPreferenceLocalRecovery.requireWithinLimit(
                localPreferences: localPreferences,
                remoteScientificNames: Set(remoteByScientificName.keys),
                pendingDeletes: pendingDeletes,
                maximumCount: maximumLocalPreferenceCount
            )

            localPreferences = try SpeciesPreferenceLocalRecovery.recover(
                localPreferences: localPreferences,
                pendingDeletes: &pendingDeletes,
                ownerUserID: ownerUserID,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
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
                    guard let capturedDeleteDate = pendingDeletes[
                        upsert.scientific_name
                    ] else {
                        continue
                    }
                    SpeciesPreferredNameStore.clearPendingCloudDelete(
                        for: upsert.scientific_name,
                        ownerUserID: ownerUserID,
                        ifNotNewerThan: capturedDeleteDate,
                        userDefaults: legacyDefaults
                    )
                }

                // The upsert suspension can overlap a local edit. Refresh the
                // local snapshot before applying the earlier remote response so
                // stale reconciliation cannot overwrite that edit.
                localPreferences = try canonicalLocalPreferences(
                    fetchAllPreferences(
                        ownerUserID: ownerUserID,
                        modelContext: modelContext
                    )
                )
                pendingDeletes = SpeciesPreferredNameStore.pendingDeleteDates(
                    ownerUserID: ownerUserID,
                    userDefaults: legacyDefaults
                )
                try SpeciesPreferenceLocalRecovery
                    .requireWithinLimit(
                        localPreferences: localPreferences,
                        remoteScientificNames: Set(
                            remoteByScientificName.keys
                        ),
                        pendingDeletes: pendingDeletes,
                        maximumCount: maximumLocalPreferenceCount
                    )
            }

            try requireCurrentAccountWork(accountWorkLease)
            try applyRemotePreferences(
                Array(remoteByScientificName.values),
                localPreferences: localPreferences,
                pendingDeletes: pendingDeletes,
                ownerUserID: ownerUserID,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            SpeciesPreferredNameStore.recordSyncSuccess(
                ownerUserID: ownerUserID,
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
                ownerUserID: ownerUserID,
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
        ownerUserID: UUID,
        modelContext: ModelContext
    ) throws -> [UserSpeciesPreference] {
        let ownerID = ownerUserID.uuidString.lowercased()
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate { $0.ownerUserId == ownerID },
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        descriptor.fetchLimit = maximumLocalPreferenceCount + 1

        do {
            let preferences = try modelContext.fetch(descriptor)
            guard preferences.count <= maximumLocalPreferenceCount else {
                throw SpeciesPreferenceCloudSyncError
                    .preferenceLimitExceeded(
                        limit: maximumLocalPreferenceCount
                    )
            }
            return preferences
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

        var cursor: String?
        while true {
            let remainingCapacity = maximumLocalPreferenceCount + 1
                - rows.count
            let requestSize = min(pageSize, remainingCapacity)
            let page = try await client.fetchPage(
                SpeciesPreferenceCloudPageRequest(
                    userID: userID,
                    afterScientificName: cursor,
                    pageSize: requestSize
                )
            )
            try requireCurrentAccountWork(accountWorkLease)

            rows.append(contentsOf: page)
            guard rows.count <= maximumLocalPreferenceCount else {
                throw SpeciesPreferenceCloudSyncError
                    .preferenceLimitExceeded(
                        limit: maximumLocalPreferenceCount
                    )
            }
            if page.count < requestSize { break }

            guard let nextCursor = page.last?.scientific_name,
                  nextCursor != cursor else {
                throw SpeciesPreferenceCloudSyncError
                    .invalidPaginationCursor
            }
            cursor = nextCursor
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
        ownerUserID: UUID,
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
                    ownerUserID: ownerUserID,
                    scientificName: scientificName,
                    preferredCommonName: remotePreferredName,
                    updatedAt: remoteUpdatedAt
                )
                modelContext.insert(preference)
                localByScientificName[scientificName] = preference
            }
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

        for scientificName in pendingDeletesToClear {
            guard let capturedDeleteDate = pendingDeletes[scientificName]
            else {
                continue
            }
            SpeciesPreferredNameStore.clearPendingCloudDelete(
                for: scientificName,
                ownerUserID: ownerUserID,
                ifNotNewerThan: capturedDeleteDate,
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
