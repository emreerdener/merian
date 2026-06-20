import Combine
import Foundation
import Observation
import Supabase
import SwiftData
import UIKit

// MARK: - UserDefaults Key Constants
/// Single source of truth for all UserDefaults / AppStorage key strings.
/// Using these constants prevents silent key mismatches across sites that
/// read and write the same preference value.
enum UserDefaultsKeys {
    /// Whether onboarding has completed and the full app lifecycle may start.
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    /// The current theme mode selection persisted via AppStorage.
    static let themeMode = "themeMode"
    /// Whether multi-capture mode is enabled for the camera workflow.
    static let isMultiCaptureEnabled = "isMultiCaptureEnabled"
    /// Whether scans should wait for explicit user confirmation before submission.
    static let requiresScanConfirmation = "requiresScanConfirmation"
    /// Legacy pre-migration key for the old multi-image scan mode toggle.
    static let legacyMultiImageScanMode = "multiImageScanMode"
    /// Whether expedition mode is active for low-power field capture sessions.
    static let isExpeditionModeActive = "isExpeditionModeActive"
    /// Whether haptic feedback is enabled globally.
    static let isHapticsEnabled = "isHapticsEnabled"
    /// Whether the user has an unseen scan result waiting in the Scans sheet.
    static let hasUnseenScan = "hasUnseenScan"
    /// Whether discovery-complete notifications are enabled.
    static let isPushNotificationsEnabled = "isPushNotificationsEnabled"
    /// Whether the OS has granted notification authorization for this app.
    static let hasPushNotificationAuthorization = "hasPushNotificationAuthorization"
    /// Whether achievement notifications are enabled.
    static let isAchievementNotificationsEnabled = "isAchievementNotificationsEnabled"
    /// Whether Explore activity notifications are enabled.
    static let isExploreNotificationsEnabled = "isExploreNotificationsEnabled"
    /// Whether Explore comment mention push notifications are enabled.
    static let isExploreCommentMentionNotificationsEnabled = "isExploreCommentMentionNotificationsEnabled"
    /// Last APNs device token registered by the app, stored as lowercase hex.
    static let remotePushDeviceToken = "remotePushDeviceToken"
    /// Whether the live on-device inference viewfinder pass is paused (Legacy Viewfinder mode).
    static let isLiveInferencePaused = "isLiveInferencePaused"
    /// Whether swipe-to-zoom direction is inverted (down = zoom in, up = zoom out).
    static let invertZoomDirection = "invertZoomDirection"
    /// Whether the zoom slider is placed on the left side of the viewfinder instead of the right.
    static let zoomSideLeft = "zoomSideLeft"
    /// Whether the zoom slider overlay is visible on the camera viewfinder.
    static let zoomSliderVisible = "zoomSliderVisible"
    /// Whether captured images should also be saved to the iOS camera roll.
    static let saveToCameraRoll = "saveToCameraRoll"
    /// Whether live audio placement hints are visible while recording.
    static let audioHintsEnabled = "audioHintsEnabled"
    /// User-selected column count for the scans library grid.
    static let gridColumns = "gridColumns"
    /// Whether local `ScanCollection` changes are pending a push to the `sync-collections` Edge function.
    static let needsCollectionSync = "needsCollectionSync"
    /// Locally hidden smart collection ids, stored as a string array.
    static let hiddenSmartCollectionIDs = "hiddenSmartCollectionIDs"
    /// Prefix for per-species preferred common name. Append the scientific name to form the full key.
    /// e.g. `"speciesPreferredName_Gaillardia pulchella"` → user's chosen display name.
    static let speciesPreferredNamePrefix = "speciesPreferredName_"
    /// Dictionary of scientific name → delete timestamp for preferred-name clears waiting for cloud sync.
    static let pendingSpeciesPreferredNameDeletes = "pendingSpeciesPreferredNameDeletes"
    /// Last wall-clock attempt for preferred-name cloud sync.
    static let speciesPreferredNameSyncLastAttemptAt = "speciesPreferredNameSyncLastAttemptAt"
    /// Last successful preferred-name cloud sync completion time.
    static let speciesPreferredNameSyncLastSuccessAt = "speciesPreferredNameSyncLastSuccessAt"
    /// Last preferred-name cloud sync state: running, success, failure, or skipped.
    static let speciesPreferredNameSyncStatus = "speciesPreferredNameSyncStatus"
    /// Human-readable preferred-name cloud sync failure/skip reason for support diagnostics.
    static let speciesPreferredNameSyncMessage = "speciesPreferredNameSyncMessage"
    /// Number of preferred-name rows pushed during the last successful cloud sync.
    static let speciesPreferredNameSyncLastPushedCount = "speciesPreferredNameSyncLastPushedCount"
    /// Number of preferred-name rows pulled during the last successful cloud sync.
    static let speciesPreferredNameSyncLastPulledCount = "speciesPreferredNameSyncLastPulledCount"
    /// Whether the user has been presented with the notification request post-identification.
    static let hasPromptedForNotificationsPostIdent = "hasPromptedForNotificationsPostIdent"
    /// The user's customized ordering of the primary capture tabs, stored as a comma-separated string.
    static let captureModeOrder = "captureModeOrder"
    /// Whether the user has seen the one-time Explore onboarding prompt.
    static let hasSeenExploreOnboarding = "hasSeenExploreOnboarding"
    /// Whether the user has dismissed the one-time Explore tab "New" chip.
    static let hasSeenExploreNewChip = "hasSeenExploreNewChip"
    /// Whether the Explore feed has a newer post than the one the user most recently saw.
    static let hasUnseenExplorePost = "hasUnseenExplorePost"
    /// One-time feedback survey campaign id the user dismissed.
    static let feedbackSurveyDismissedCampaignId = "feedbackSurveyDismissedCampaignId"
    /// One-time feedback survey campaign id the user submitted.
    static let feedbackSurveySubmittedCampaignId = "feedbackSurveySubmittedCampaignId"
    /// Seconds-since-epoch timestamp for the latest feedback survey submission.
    static let feedbackSurveySubmittedAt = "feedbackSurveySubmittedAt"
    /// Prefix for per-scan Explore share state. Append the local `scanId` to form the full key.
    /// e.g. `"sharedExplorePostId_1234-uuid"` → the published Explore post id for that scan.
    static let sharedExplorePostIdPrefix = "sharedExplorePostId_"
    /// Legacy prefix for per-scan field notes used by the temporary bridge implementation.
    /// Retained so existing local drafts can be migrated into SwiftData-backed scan records.
    static let fieldNotesPrefix = "fieldNotes_"
    /// The `sharedAt` timestamp of the newest Explore post successfully loaded by the user.
    static let lastSeenExplorePostSharedAt = "lastSeenExplorePostSharedAt"
    /// Whether foreground inference-complete banners should be suppressed while the user is already viewing results.
    static let suppressInferenceBanners = "suppressInferenceBanners"
    /// Seconds-since-epoch timestamp recorded when the app moves to the background.
    static let lastBackgroundedDate = "lastBackgroundedDate"
    /// Throttle marker for the last historical cloud-to-local sync attempt.
    static let lastHistoricalSyncDate = "lastHistoricalSyncDate"
    /// A persisted 24-hour TTL dictionary of species that have already completed enrichment.
    static let enrichedSpeciesTimestamps = "enrichedSpeciesTimestamps"
    /// Version marker for one-time local similar-species cache resets.
    static let localLookalikesCacheResetVersion = "localLookalikesCacheResetVersion"
}

enum KeychainKeys {
    /// Distinguishes OAuth-authenticated users from anonymous ghost sessions.
    static let hasAuthenticatedOAuth = "Merian_HasAuthenticatedOAuth"
}

enum ScanLibraryEvents {
    private static let searchIndexUpdateUserInfoKey = "scanId"

    static let searchIndexUpdate = Notification.Name("ScanRequiresSearchIndexUpdate")
    static let libraryDidUpdate = Notification.Name("MerianLibraryDidUpdate")

    static func postSearchIndexUpdate(
        scanId: String,
        center: NotificationCenter = .default
    ) {
        center.post(
            name: searchIndexUpdate,
            object: nil,
            userInfo: [searchIndexUpdateUserInfoKey: scanId]
        )
    }

    static func scanId(from notification: Notification) -> String? {
        notification.userInfo?[searchIndexUpdateUserInfoKey] as? String
    }

    static func searchIndexUpdatePublisher(
        center: NotificationCenter = .default
    ) -> NotificationCenter.Publisher {
        center.publisher(for: searchIndexUpdate)
    }

    static func postLibraryDidUpdate(center: NotificationCenter = .default) {
        center.post(name: libraryDidUpdate, object: nil)
    }

    static func libraryDidUpdatePublisher(
        center: NotificationCenter = .default
    ) -> NotificationCenter.Publisher {
        center.publisher(for: libraryDidUpdate)
    }
}

enum ExploreShareStateStore {
    private static func key(for scanId: String) -> String {
        UserDefaultsKeys.sharedExplorePostIdPrefix + scanId
    }

    static func sharedPostId(for scanId: String, userDefaults: UserDefaults = .standard) -> String? {
        let value = userDefaults.string(forKey: key(for: scanId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setSharedPostId(_ postId: String?, for scanId: String, userDefaults: UserDefaults = .standard) {
        let trimmed = postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            userDefaults.set(trimmed, forKey: key(for: scanId))
        } else {
            userDefaults.removeObject(forKey: key(for: scanId))
        }
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.sharedExplorePostIdPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }
}

enum FieldNotesStore {
    private static func key(for scanId: String) -> String {
        UserDefaultsKeys.fieldNotesPrefix + scanId
    }

    static func fieldNotes(for scanId: String, userDefaults: UserDefaults = .standard) -> String? {
        let value = userDefaults.string(forKey: key(for: scanId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setFieldNotes(_ fieldNotes: String?, for scanId: String, userDefaults: UserDefaults = .standard) {
        let trimmed = fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fieldNotes, trimmed?.isEmpty == false {
            userDefaults.set(fieldNotes, forKey: key(for: scanId))
        } else {
            userDefaults.removeObject(forKey: key(for: scanId))
        }
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.fieldNotesPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }
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

struct SpeciesNameMigrationResult: Equatable {
    let scannedCount: Int
    let promotedCount: Int
    let preservedExistingCount: Int
    let removedLegacyCount: Int
    let failedCount: Int
}

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

private struct SpeciesPreferenceCloudRow: Decodable {
    let scientific_name: String
    let preferred_common_name: String?
    let updated_at: String
    let deleted_at: String?
}

private struct SpeciesPreferenceCloudUpsert: Encodable {
    let user_id: String
    let scientific_name: String
    let preferred_common_name: String?
    let deleted_at: String?

    enum CodingKeys: String, CodingKey {
        case user_id
        case scientific_name
        case preferred_common_name
        case deleted_at
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(scientific_name, forKey: .scientific_name)

        if let preferred_common_name {
            try container.encode(preferred_common_name, forKey: .preferred_common_name)
        } else {
            try container.encodeNil(forKey: .preferred_common_name)
        }

        if let deleted_at {
            try container.encode(deleted_at, forKey: .deleted_at)
        } else {
            try container.encodeNil(forKey: .deleted_at)
        }
    }
}

@MainActor
enum SpeciesPreferredNameRepository {
    private struct PendingCloudSyncRequest {
        let modelContext: ModelContext
        let legacyDefaults: UserDefaults
        let force: Bool
    }

    private static let maxPreferredNameBatchSize = 1_000
    private static let cloudSyncPageSize = 500
    private static let cleanCloudSyncFreshnessInterval: TimeInterval = 60
    private static var activeCloudSyncTask: Task<Bool, Never>?
    private static var pendingCloudSyncRequest: PendingCloudSyncRequest?

    static func preferredName(
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> String? {
        let scientificName = normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return nil }

        if let record = fetchPreference(for: scientificName, modelContext: modelContext) {
            let preferredName = normalizedPreferredName(record.preferredCommonName)
            if let preferredName {
                SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
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
                    .map(normalizedScientificName)
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()

        if normalizedNames.count > maxPreferredNameBatchSize {
            MerianLog.data.error(
                "Truncating species preferred-name batch from \(normalizedNames.count, privacy: .public) to \(maxPreferredNameBatchSize, privacy: .public)"
            )
        }

        var namesByScientificName: [String: String] = [:]
        let boundedNames = Array(normalizedNames.prefix(maxPreferredNameBatchSize))
        let recordsByScientificName = fetchPreferences(for: boundedNames, modelContext: modelContext)
        namesByScientificName.reserveCapacity(boundedNames.count)

        for scientificName in boundedNames {
            if let record = recordsByScientificName[scientificName],
               let preferredName = normalizedPreferredName(record.preferredCommonName) {
                SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
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
    static func syncCloudPreferences(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard,
        force: Bool = false
    ) async -> Bool {
        guard !TestExecutionCoordinator.isRunningTests else { return false }
        if let activeCloudSyncTask {
            let shouldForce = force || pendingCloudSyncRequest?.force == true
            pendingCloudSyncRequest = PendingCloudSyncRequest(
                modelContext: modelContext,
                legacyDefaults: legacyDefaults,
                force: shouldForce
            )
            return await activeCloudSyncTask.value
        }
        guard force || !hasFreshCleanCloudSync(legacyDefaults: legacyDefaults) else {
            return true
        }

        let syncTask = Task { @MainActor in
            defer {
                activeCloudSyncTask = nil
                pendingCloudSyncRequest = nil
            }

            var nextModelContext = modelContext
            var nextLegacyDefaults = legacyDefaults

            while true {
                let latestResult = await performCloudPreferenceSync(
                    modelContext: nextModelContext,
                    legacyDefaults: nextLegacyDefaults
                )

                guard let pendingCloudSyncRequest else {
                    return latestResult
                }

                nextModelContext = pendingCloudSyncRequest.modelContext
                nextLegacyDefaults = pendingCloudSyncRequest.legacyDefaults
                SpeciesPreferredNameRepository.pendingCloudSyncRequest = nil
            }
        }
        activeCloudSyncTask = syncTask
        return await syncTask.value
    }

    private static func hasFreshCleanCloudSync(legacyDefaults: UserDefaults) -> Bool {
        guard SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: legacyDefaults).isEmpty else {
            return false
        }
        guard let lastSuccessAt = SpeciesPreferredNameStore.syncDiagnostics(userDefaults: legacyDefaults).lastSuccessAt else {
            return false
        }
        return Date().timeIntervalSince(lastSuccessAt) < cleanCloudSyncFreshnessInterval
    }

    private static func performCloudPreferenceSync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) async -> Bool {
        SpeciesPreferredNameStore.recordSyncAttempt(userDefaults: legacyDefaults)

        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id.uuidString else {
            SpeciesPreferredNameStore.recordSyncSkip(
                "No authenticated Supabase user.",
                userDefaults: legacyDefaults
            )
            return false
        }

        do {
            let localPreferences = fetchAllPreferences(modelContext: modelContext)
            let pendingDeletes = SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: legacyDefaults)
            let remoteRows = try await fetchRemotePreferences(userId: userId)
            let remoteByScientificName = Dictionary(
                uniqueKeysWithValues: remoteRows.map {
                    (normalizedScientificName($0.scientific_name), $0)
                }
            )

            let activeUpserts = activeCloudUpserts(
                userId: userId,
                localPreferences: localPreferences,
                remoteByScientificName: remoteByScientificName
            )
            let deleteUpserts = pendingDeleteUpserts(
                userId: userId,
                pendingDeletes: pendingDeletes,
                remoteByScientificName: remoteByScientificName
            )
            let upserts = activeUpserts + deleteUpserts

            if !upserts.isEmpty {
                try await SupabaseManager.shared.client
                    .from("user_species_preferences")
                    .upsert(upserts, onConflict: "user_id,scientific_name")
                    .execute()

                for upsert in deleteUpserts {
                    SpeciesPreferredNameStore.clearPendingCloudDelete(
                        for: upsert.scientific_name,
                        userDefaults: legacyDefaults
                    )
                }
            }

            applyRemotePreferences(
                remoteRows,
                localPreferences: localPreferences,
                pendingDeletes: pendingDeletes,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            SpeciesPreferredNameStore.recordSyncSuccess(
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
                userDefaults: legacyDefaults
            )
            MerianLog.data.debug("Species preferred-name cloud sync skipped or failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    @discardableResult
    static func migrateLegacyPreferences(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> SpeciesNameMigrationResult {
        let legacyPreferences = SpeciesPreferredNameStore.legacyPreferences(userDefaults: legacyDefaults)
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
        let recordsByScientificName = fetchPreferences(for: scientificNames, modelContext: modelContext)

        var didMutateSwiftData = false
        var pendingPromotedCount = 0
        var preservedExistingCount = 0

        for scientificName in scientificNames {
            guard let legacyName = normalizedPreferredName(legacyPreferences[scientificName]) else { continue }

            if let existing = recordsByScientificName[scientificName],
               normalizedPreferredName(existing.preferredCommonName) != nil {
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
                SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
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
            MerianLog.data.error("Failed to migrate legacy species preferred names: \(error.localizedDescription, privacy: .private)")
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
        let scientificName = normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        guard let preferredName = normalizedPreferredName(name) else {
            return clearPreferredName(
                for: scientificName,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
        }

        do {
            if let existing = fetchPreference(for: scientificName, modelContext: modelContext) {
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
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.clearPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            scheduleCloudSync(modelContext: modelContext, legacyDefaults: legacyDefaults)
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("Failed to save species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    @discardableResult
    static func clearPreferredName(
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        let scientificName = normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        guard let existing = fetchPreference(for: scientificName, modelContext: modelContext) else {
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.markPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            return true
        }

        do {
            modelContext.delete(existing)
            try modelContext.save()
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.markPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            scheduleCloudSync(modelContext: modelContext, legacyDefaults: legacyDefaults)
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("Failed to clear species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private static func fetchPreference(
        for scientificName: String,
        modelContext: ModelContext
    ) -> UserSpeciesPreference? {
        let targetScientificName = scientificName
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate<UserSpeciesPreference> { $0.scientificName == targetScientificName }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.error("Failed to fetch species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private static func fetchPreferences(
        for scientificNames: [String],
        modelContext: ModelContext
    ) -> [String: UserSpeciesPreference] {
        guard !scientificNames.isEmpty else { return [:] }

        let targetScientificNames = scientificNames
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate<UserSpeciesPreference> { targetScientificNames.contains($0.scientificName) }
        )
        descriptor.fetchLimit = targetScientificNames.count

        do {
            let records = try modelContext.fetch(descriptor)
            var recordsByScientificName: [String: UserSpeciesPreference] = [:]
            recordsByScientificName.reserveCapacity(records.count)
            for record in records where recordsByScientificName[record.scientificName] == nil {
                recordsByScientificName[record.scientificName] = record
            }
            return recordsByScientificName
        } catch {
            MerianLog.data.error("Failed to batch fetch species preferred names: \(error.localizedDescription, privacy: .private)")
            return [:]
        }
    }

    private static func fetchAllPreferences(modelContext: ModelContext) -> [UserSpeciesPreference] {
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        descriptor.fetchLimit = maxPreferredNameBatchSize

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error("Failed to fetch local species preferred names for cloud sync: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    private static func fetchRemotePreferences(userId: String) async throws -> [SpeciesPreferenceCloudRow] {
        var rows: [SpeciesPreferenceCloudRow] = []
        rows.reserveCapacity(cloudSyncPageSize)

        var offset = 0
        while true {
            let page: [SpeciesPreferenceCloudRow] = try await SupabaseManager.shared.client
                .from("user_species_preferences")
                .select("scientific_name, preferred_common_name, updated_at, deleted_at")
                .eq("user_id", value: userId)
                .order("updated_at", ascending: true)
                .range(from: offset, to: offset + cloudSyncPageSize - 1)
                .execute()
                .value

            rows.append(contentsOf: page)
            if page.count < cloudSyncPageSize { break }
            offset += cloudSyncPageSize
        }

        return rows
    }

    private static func activeCloudUpserts(
        userId: String,
        localPreferences: [UserSpeciesPreference],
        remoteByScientificName: [String: SpeciesPreferenceCloudRow]
    ) -> [SpeciesPreferenceCloudUpsert] {
        localPreferences.compactMap { preference in
            let scientificName = normalizedScientificName(preference.scientificName)
            guard !scientificName.isEmpty,
                  let preferredName = normalizedPreferredName(preference.preferredCommonName) else {
                return nil
            }

            if let remote = remoteByScientificName[scientificName],
               let remoteUpdatedAt = cloudDate(remote.updated_at),
               remoteUpdatedAt > preference.updatedAt {
                return nil
            }

            return SpeciesPreferenceCloudUpsert(
                user_id: userId,
                scientific_name: scientificName,
                preferred_common_name: preferredName,
                deleted_at: nil
            )
        }
    }

    private static func pendingDeleteUpserts(
        userId: String,
        pendingDeletes: [String: Date],
        remoteByScientificName: [String: SpeciesPreferenceCloudRow]
    ) -> [SpeciesPreferenceCloudUpsert] {
        pendingDeletes.compactMap { scientificName, deletedAt in
            let scientificName = normalizedScientificName(scientificName)
            guard !scientificName.isEmpty else { return nil }

            if let remote = remoteByScientificName[scientificName],
               let remoteUpdatedAt = cloudDate(remote.updated_at),
               remoteUpdatedAt > deletedAt {
                return nil
            }

            return SpeciesPreferenceCloudUpsert(
                user_id: userId,
                scientific_name: scientificName,
                preferred_common_name: nil,
                deleted_at: cloudString(deletedAt)
            )
        }
    }

    private static func applyRemotePreferences(
        _ remoteRows: [SpeciesPreferenceCloudRow],
        localPreferences: [UserSpeciesPreference],
        pendingDeletes: [String: Date],
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) {
        guard !remoteRows.isEmpty else { return }

        var localByScientificName = Dictionary(
            uniqueKeysWithValues: localPreferences.map {
                (normalizedScientificName($0.scientificName), $0)
            }
        )
        var didMutate = false

        for remote in remoteRows {
            let scientificName = normalizedScientificName(remote.scientific_name)
            guard !scientificName.isEmpty,
                  let remoteUpdatedAt = cloudDate(remote.updated_at) else {
                continue
            }

            if let pendingDelete = pendingDeletes[scientificName],
               pendingDelete >= remoteUpdatedAt {
                continue
            }

            if remote.deleted_at != nil {
                if let localPreference = localByScientificName[scientificName],
                   remoteUpdatedAt >= localPreference.updatedAt {
                    modelContext.delete(localPreference)
                    localByScientificName.removeValue(forKey: scientificName)
                    SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
                    didMutate = true
                }
                SpeciesPreferredNameStore.clearPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
                continue
            }

            guard let remotePreferredName = normalizedPreferredName(remote.preferred_common_name) else {
                continue
            }

            if let localPreference = localByScientificName[scientificName] {
                guard remoteUpdatedAt > localPreference.updatedAt else { continue }
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
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.clearPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            didMutate = true
        }

        guard didMutate else { return }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("Failed to apply remote species preferred names: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func cloudString(_ date: Date) -> String {
        DateUtilities.iso8601FractionalFormatter.string(from: date)
    }

    private static func cloudDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return DateUtilities.iso8601FractionalFormatter.date(from: value)
            ?? DateUtilities.iso8601Formatter.date(from: value)
    }

    private static func scheduleCloudSync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        Task { @MainActor in
            await syncCloudPreferences(modelContext: modelContext, legacyDefaults: legacyDefaults, force: true)
        }
    }

    private static func normalizedScientificName(_ scientificName: String) -> String {
        scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPreferredName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var isReloadingFromDefaults = false

    var hasCompletedOnboarding: Bool {
        didSet { persistBool(hasCompletedOnboarding, oldValue: oldValue, key: UserDefaultsKeys.hasCompletedOnboarding) }
    }
    var themeMode: ThemeMode {
        didSet { persistString(themeMode.rawValue, oldValue: oldValue.rawValue, key: UserDefaultsKeys.themeMode) }
    }
    var isMultiCaptureEnabled: Bool {
        didSet { persistBool(isMultiCaptureEnabled, oldValue: oldValue, key: UserDefaultsKeys.isMultiCaptureEnabled) }
    }
    var requiresScanConfirmation: Bool {
        didSet {
            persistBool(requiresScanConfirmation, oldValue: oldValue, key: UserDefaultsKeys.requiresScanConfirmation)
            ShareImportSharedStateWriter.refresh()
        }
    }
    var isExpeditionModeActive: Bool {
        didSet { persistBool(isExpeditionModeActive, oldValue: oldValue, key: UserDefaultsKeys.isExpeditionModeActive) }
    }
    var isHapticsEnabled: Bool {
        didSet { persistBool(isHapticsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isHapticsEnabled) }
    }
    var hasUnseenScan: Bool {
        didSet { persistBool(hasUnseenScan, oldValue: oldValue, key: UserDefaultsKeys.hasUnseenScan) }
    }
    var isPushNotificationsEnabled: Bool {
        didSet { persistBool(isPushNotificationsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isPushNotificationsEnabled) }
    }
    var hasPromptedForNotificationsPostIdent: Bool {
        didSet { persistBool(hasPromptedForNotificationsPostIdent, oldValue: oldValue, key: UserDefaultsKeys.hasPromptedForNotificationsPostIdent) }
    }
    var isAchievementNotificationsEnabled: Bool {
        didSet { persistBool(isAchievementNotificationsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isAchievementNotificationsEnabled) }
    }
    var isExploreNotificationsEnabled: Bool {
        didSet { persistBool(isExploreNotificationsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isExploreNotificationsEnabled) }
    }
    var isExploreCommentMentionNotificationsEnabled: Bool {
        didSet {
            persistBool(
                isExploreCommentMentionNotificationsEnabled,
                oldValue: oldValue,
                key: UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
            )
        }
    }
    var hasSeenExploreOnboarding: Bool {
        didSet { persistBool(hasSeenExploreOnboarding, oldValue: oldValue, key: UserDefaultsKeys.hasSeenExploreOnboarding) }
    }
    var hasSeenExploreNewChip: Bool {
        didSet { persistBool(hasSeenExploreNewChip, oldValue: oldValue, key: UserDefaultsKeys.hasSeenExploreNewChip) }
    }
    var hasUnseenExplorePost: Bool {
        didSet { persistBool(hasUnseenExplorePost, oldValue: oldValue, key: UserDefaultsKeys.hasUnseenExplorePost) }
    }
    var lastSeenExplorePostSharedAt: String {
        didSet { persistString(lastSeenExplorePostSharedAt, oldValue: oldValue, key: UserDefaultsKeys.lastSeenExplorePostSharedAt) }
    }
    var feedbackSurveyDismissedCampaignId: String {
        didSet {
            persistString(
                feedbackSurveyDismissedCampaignId,
                oldValue: oldValue,
                key: UserDefaultsKeys.feedbackSurveyDismissedCampaignId
            )
        }
    }
    var feedbackSurveySubmittedCampaignId: String {
        didSet {
            persistString(
                feedbackSurveySubmittedCampaignId,
                oldValue: oldValue,
                key: UserDefaultsKeys.feedbackSurveySubmittedCampaignId
            )
        }
    }
    var feedbackSurveySubmittedAt: TimeInterval {
        didSet {
            persistDouble(
                feedbackSurveySubmittedAt,
                oldValue: oldValue,
                key: UserDefaultsKeys.feedbackSurveySubmittedAt
            )
        }
    }
    var invertZoomDirection: Bool {
        didSet { persistBool(invertZoomDirection, oldValue: oldValue, key: UserDefaultsKeys.invertZoomDirection) }
    }
    var zoomSideLeft: Bool {
        didSet { persistBool(zoomSideLeft, oldValue: oldValue, key: UserDefaultsKeys.zoomSideLeft) }
    }
    var zoomSliderVisible: Bool {
        didSet { persistBool(zoomSliderVisible, oldValue: oldValue, key: UserDefaultsKeys.zoomSliderVisible) }
    }
    var isLiveInferencePaused: Bool {
        didSet { persistBool(isLiveInferencePaused, oldValue: oldValue, key: UserDefaultsKeys.isLiveInferencePaused) }
    }
    var suppressInferenceBanners: Bool {
        didSet { persistBool(suppressInferenceBanners, oldValue: oldValue, key: UserDefaultsKeys.suppressInferenceBanners) }
    }
    var saveToCameraRoll: Bool {
        didSet { persistBool(saveToCameraRoll, oldValue: oldValue, key: UserDefaultsKeys.saveToCameraRoll) }
    }
    var audioHintsEnabled: Bool {
        didSet { persistBool(audioHintsEnabled, oldValue: oldValue, key: UserDefaultsKeys.audioHintsEnabled) }
    }
    var captureModeOrderRaw: String {
        didSet { persistString(captureModeOrderRaw, oldValue: oldValue, key: UserDefaultsKeys.captureModeOrder) }
    }
    var gridColumns: Int {
        didSet {
            let normalized = min(max(gridColumns, 1), 3)
            if gridColumns != normalized {
                gridColumns = normalized
                return
            }
            persistInt(gridColumns, oldValue: oldValue, key: UserDefaultsKeys.gridColumns)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        observeExternalChanges: Bool = true
    ) {
        self.userDefaults = userDefaults

        userDefaults.register(defaults: [
            UserDefaultsKeys.themeMode: ThemeMode.system.rawValue,
            UserDefaultsKeys.isMultiCaptureEnabled: false,
            UserDefaultsKeys.requiresScanConfirmation: false,
            UserDefaultsKeys.isExpeditionModeActive: false,
            UserDefaultsKeys.isHapticsEnabled: true,
            UserDefaultsKeys.hasUnseenScan: false,
            UserDefaultsKeys.isPushNotificationsEnabled: false,
            UserDefaultsKeys.hasPromptedForNotificationsPostIdent: false,
            UserDefaultsKeys.isAchievementNotificationsEnabled: true,
            UserDefaultsKeys.isExploreNotificationsEnabled: true,
            UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled: true,
            UserDefaultsKeys.hasSeenExploreOnboarding: false,
            UserDefaultsKeys.hasSeenExploreNewChip: false,
            UserDefaultsKeys.hasUnseenExplorePost: false,
            UserDefaultsKeys.lastSeenExplorePostSharedAt: "",
            UserDefaultsKeys.feedbackSurveyDismissedCampaignId: "",
            UserDefaultsKeys.feedbackSurveySubmittedCampaignId: "",
            UserDefaultsKeys.feedbackSurveySubmittedAt: 0,
            UserDefaultsKeys.invertZoomDirection: false,
            UserDefaultsKeys.zoomSideLeft: true,
            UserDefaultsKeys.zoomSliderVisible: true,
            UserDefaultsKeys.isLiveInferencePaused: UIDevice.current.isModernIPhone,
            UserDefaultsKeys.suppressInferenceBanners: false,
            UserDefaultsKeys.saveToCameraRoll: false,
            UserDefaultsKeys.audioHintsEnabled: true,
            UserDefaultsKeys.captureModeOrder: "visual,audio,describe",
            UserDefaultsKeys.gridColumns: 3
        ])

        hasCompletedOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        themeMode = ThemeMode(
            rawValue: userDefaults.string(forKey: UserDefaultsKeys.themeMode) ?? ThemeMode.system.rawValue
        ) ?? .system
        isMultiCaptureEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isMultiCaptureEnabled)
        requiresScanConfirmation = userDefaults.bool(forKey: UserDefaultsKeys.requiresScanConfirmation)
        isExpeditionModeActive = userDefaults.bool(forKey: UserDefaultsKeys.isExpeditionModeActive)
        isHapticsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isHapticsEnabled)
        hasUnseenScan = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenScan)
        isPushNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled)
        hasPromptedForNotificationsPostIdent = userDefaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent)
        isAchievementNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
        isExploreNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isExploreNotificationsEnabled)
        isExploreCommentMentionNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
        )
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
        hasSeenExploreNewChip = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreNewChip)
        hasUnseenExplorePost = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost)
        lastSeenExplorePostSharedAt = userDefaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) ?? ""
        feedbackSurveyDismissedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveyDismissedCampaignId) ?? ""
        feedbackSurveySubmittedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveySubmittedCampaignId) ?? ""
        feedbackSurveySubmittedAt = userDefaults.double(forKey: UserDefaultsKeys.feedbackSurveySubmittedAt)
        invertZoomDirection = userDefaults.bool(forKey: UserDefaultsKeys.invertZoomDirection)
        zoomSideLeft = userDefaults.bool(forKey: UserDefaultsKeys.zoomSideLeft)
        zoomSliderVisible = userDefaults.bool(forKey: UserDefaultsKeys.zoomSliderVisible)
        isLiveInferencePaused = userDefaults.object(forKey: UserDefaultsKeys.isLiveInferencePaused) as? Bool
            ?? UIDevice.current.isModernIPhone
        suppressInferenceBanners = userDefaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners)
        saveToCameraRoll = userDefaults.bool(forKey: UserDefaultsKeys.saveToCameraRoll)
        audioHintsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.audioHintsEnabled)
        captureModeOrderRaw = userDefaults.string(forKey: UserDefaultsKeys.captureModeOrder) ?? "visual,audio,describe"
        gridColumns = min(max(userDefaults.integer(forKey: UserDefaultsKeys.gridColumns), 1), 3)

        if observeExternalChanges {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: userDefaults,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reloadFromDefaults()
                }
            }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func applyCaptureModeOrder(_ modes: [CaptureMode]) {
        captureModeOrderRaw = modes.map(\.rawValue).joined(separator: ",")
    }

    func refreshFromDefaults() {
        reloadFromDefaults()
    }

    private func reloadFromDefaults() {
        isReloadingFromDefaults = true
        defer { isReloadingFromDefaults = false }

        hasCompletedOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        themeMode = ThemeMode(
            rawValue: userDefaults.string(forKey: UserDefaultsKeys.themeMode) ?? ThemeMode.system.rawValue
        ) ?? .system
        isMultiCaptureEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isMultiCaptureEnabled)
        requiresScanConfirmation = userDefaults.bool(forKey: UserDefaultsKeys.requiresScanConfirmation)
        isExpeditionModeActive = userDefaults.bool(forKey: UserDefaultsKeys.isExpeditionModeActive)
        isHapticsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isHapticsEnabled)
        hasUnseenScan = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenScan)
        isPushNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled)
        hasPromptedForNotificationsPostIdent = userDefaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent)
        isAchievementNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
        isExploreNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isExploreNotificationsEnabled)
        isExploreCommentMentionNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
        )
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
        hasSeenExploreNewChip = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreNewChip)
        hasUnseenExplorePost = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost)
        lastSeenExplorePostSharedAt = userDefaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) ?? ""
        feedbackSurveyDismissedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveyDismissedCampaignId) ?? ""
        feedbackSurveySubmittedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveySubmittedCampaignId) ?? ""
        feedbackSurveySubmittedAt = userDefaults.double(forKey: UserDefaultsKeys.feedbackSurveySubmittedAt)
        invertZoomDirection = userDefaults.bool(forKey: UserDefaultsKeys.invertZoomDirection)
        zoomSideLeft = userDefaults.bool(forKey: UserDefaultsKeys.zoomSideLeft)
        zoomSliderVisible = userDefaults.bool(forKey: UserDefaultsKeys.zoomSliderVisible)
        isLiveInferencePaused = userDefaults.object(forKey: UserDefaultsKeys.isLiveInferencePaused) as? Bool
            ?? UIDevice.current.isModernIPhone
        suppressInferenceBanners = userDefaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners)
        saveToCameraRoll = userDefaults.bool(forKey: UserDefaultsKeys.saveToCameraRoll)
        audioHintsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.audioHintsEnabled)
        captureModeOrderRaw = userDefaults.string(forKey: UserDefaultsKeys.captureModeOrder) ?? "visual,audio,describe"
        gridColumns = min(max(userDefaults.integer(forKey: UserDefaultsKeys.gridColumns), 1), 3)
    }

    private func persistBool(_ newValue: Bool, oldValue: Bool, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }

    private func persistInt(_ newValue: Int, oldValue: Int, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }

    private func persistDouble(_ newValue: Double, oldValue: Double, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }

    private func persistString(_ newValue: String, oldValue: String, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }
}

#if DEBUG
extension AppSettings {
    static var preview: AppSettings {
        let suiteName = "merian.preview.app-settings"
        let previewDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        previewDefaults.removePersistentDomain(forName: suiteName)
        return AppSettings(userDefaults: previewDefaults, observeExternalChanges: false)
    }
}
#endif
