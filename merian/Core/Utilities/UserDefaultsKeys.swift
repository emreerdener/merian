import Combine
import Foundation
import Observation
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
    /// Prefix for per-species preferred common name. Append the scientific name to form the full key.
    /// e.g. `"speciesPreferredName_Gaillardia pulchella"` → user's chosen display name.
    static let speciesPreferredNamePrefix = "speciesPreferredName_"
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
    /// Throttle marker for the last archive-rescue evaluation.
    static let lastArchiveRescueDate = "lastArchiveRescueDate"
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
        didSet { persistBool(requiresScanConfirmation, oldValue: oldValue, key: UserDefaultsKeys.requiresScanConfirmation) }
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
            UserDefaultsKeys.isAchievementNotificationsEnabled: false,
            UserDefaultsKeys.isExploreNotificationsEnabled: false,
            UserDefaultsKeys.hasSeenExploreOnboarding: false,
            UserDefaultsKeys.hasSeenExploreNewChip: false,
            UserDefaultsKeys.hasUnseenExplorePost: false,
            UserDefaultsKeys.lastSeenExplorePostSharedAt: "",
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
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
        hasSeenExploreNewChip = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreNewChip)
        hasUnseenExplorePost = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost)
        lastSeenExplorePostSharedAt = userDefaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) ?? ""
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
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
        hasSeenExploreNewChip = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreNewChip)
        hasUnseenExplorePost = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost)
        lastSeenExplorePostSharedAt = userDefaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) ?? ""
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
