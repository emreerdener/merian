import Foundation
import Observation
import UIKit

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
    var opensExploreOnLaunch: Bool {
        didSet {
            persistBool(opensExploreOnLaunch, oldValue: oldValue, key: UserDefaultsKeys.opensExploreOnLaunch)
        }
    }
    var isMultiCaptureEnabled: Bool {
        didSet { persistBool(isMultiCaptureEnabled, oldValue: oldValue, key: UserDefaultsKeys.isMultiCaptureEnabled) }
    }
    var requiresScanConfirmation: Bool {
        didSet {
            persistBool(requiresScanConfirmation, oldValue: oldValue, key: UserDefaultsKeys.requiresScanConfirmation)
        }
    }
    var showsCaptureGoalProgress: Bool {
        didSet {
            persistBool(
                showsCaptureGoalProgress,
                oldValue: oldValue,
                key: UserDefaultsKeys.showsCaptureGoalProgress
            )
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
    var isCommunityIdentificationNotificationsEnabled: Bool {
        didSet {
            persistBool(
                isCommunityIdentificationNotificationsEnabled,
                oldValue: oldValue,
                key: UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
            )
        }
    }
    var hasSeenExploreOnboarding: Bool {
        didSet { persistBool(hasSeenExploreOnboarding, oldValue: oldValue, key: UserDefaultsKeys.hasSeenExploreOnboarding) }
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
            }
            persistInt(normalized, oldValue: oldValue, key: UserDefaultsKeys.gridColumns)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        observeExternalChanges: Bool = true
    ) {
        self.userDefaults = userDefaults

        userDefaults.register(defaults: [
            UserDefaultsKeys.themeMode: ThemeMode.system.rawValue,
            UserDefaultsKeys.opensExploreOnLaunch: false,
            UserDefaultsKeys.isMultiCaptureEnabled: false,
            UserDefaultsKeys.requiresScanConfirmation: false,
            UserDefaultsKeys.showsCaptureGoalProgress: true,
            UserDefaultsKeys.isExpeditionModeActive: false,
            UserDefaultsKeys.isHapticsEnabled: true,
            UserDefaultsKeys.hasUnseenScan: false,
            UserDefaultsKeys.isPushNotificationsEnabled: false,
            UserDefaultsKeys.hasPromptedForNotificationsPostIdent: false,
            UserDefaultsKeys.isAchievementNotificationsEnabled: true,
            UserDefaultsKeys.isExploreNotificationsEnabled: true,
            UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled: true,
            UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled: true,
            UserDefaultsKeys.hasSeenExploreOnboarding: false,
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
        opensExploreOnLaunch = userDefaults.bool(forKey: UserDefaultsKeys.opensExploreOnLaunch)
        isMultiCaptureEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isMultiCaptureEnabled)
        requiresScanConfirmation = userDefaults.bool(forKey: UserDefaultsKeys.requiresScanConfirmation)
        showsCaptureGoalProgress = userDefaults.bool(forKey: UserDefaultsKeys.showsCaptureGoalProgress)
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
        isCommunityIdentificationNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
        )
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
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
        opensExploreOnLaunch = userDefaults.bool(forKey: UserDefaultsKeys.opensExploreOnLaunch)
        isMultiCaptureEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isMultiCaptureEnabled)
        requiresScanConfirmation = userDefaults.bool(forKey: UserDefaultsKeys.requiresScanConfirmation)
        showsCaptureGoalProgress = userDefaults.bool(forKey: UserDefaultsKeys.showsCaptureGoalProgress)
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
        isCommunityIdentificationNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
        )
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
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
