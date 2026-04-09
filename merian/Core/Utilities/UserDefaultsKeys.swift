import Foundation

// MARK: - UserDefaults Key Constants
/// Single source of truth for all UserDefaults / AppStorage key strings.
/// Using these constants prevents silent key mismatches across sites that
/// read and write the same preference value.
enum UserDefaultsKeys {
    /// Whether the user has an unseen scan result waiting in the Scans sheet.
    static let hasUnseenScan = "hasUnseenScan"
    /// Whether push notifications are enabled (mirrors OS authorization status).
    static let isPushNotificationsEnabled = "isPushNotificationsEnabled"
    /// Whether the live on-device inference viewfinder pass is paused (Legacy Viewfinder mode).
    static let isLiveInferencePaused = "isLiveInferencePaused"
    /// Whether swipe-to-zoom direction is inverted (down = zoom in, up = zoom out).
    static let invertZoomDirection = "invertZoomDirection"
    /// Whether the zoom slider is placed on the left side of the viewfinder instead of the right.
    static let zoomSideLeft = "zoomSideLeft"
    /// Whether the zoom slider overlay is visible on the camera viewfinder.
    static let zoomSliderVisible = "zoomSliderVisible"
    /// Whether local `ScanCollection` changes are pending a push to the `sync-collections` Edge function.
    static let needsCollectionSync = "needsCollectionSync"
    /// Prefix for per-species preferred common name. Append the scientific name to form the full key.
    /// e.g. `"speciesPreferredName_Gaillardia pulchella"` → user's chosen display name.
    static let speciesPreferredNamePrefix = "speciesPreferredName_"
    /// Whether the user has been presented with the notification request post-identification.
    static let hasPromptedForNotificationsPostIdent = "hasPromptedForNotificationsPostIdent"
}
