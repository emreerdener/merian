import Foundation
import PostHog
import os

/// Handles PostHog anonymous telemetry for UX funnels, retention, and feature tracking.
/// Not isolated to @MainActor — PostHogSDK is thread-safe and configure() runs on a
/// background thread via Task.detached in MerianApp.init().
final class PostHogManager {
    static let shared = PostHogManager()
    private init() {}

    private(set) var isConfigured = false

    // MARK: - Configuration

    /// Configures the PostHog SDK.
    func configure() {
        let configuration = PostHogConfig(
            apiKey: MerianEnvironment.postHogApiKey,
            host: "https://us.i.posthog.com"
        )

        // Track lifecycle events but not screen views or element interactions.
        // captureScreenViews is disabled: PostHog inserts 'UIKitToolbar' into SwiftUI
        // UIHostingController hierarchies, causing iOS 18 layout constraint warnings.
        configuration.captureApplicationLifecycleEvents = true
        configuration.captureScreenViews = false
        configuration.captureElementInteractions = false
        configuration.sessionReplay = false

        PostHogSDK.shared.setup(configuration)
        isConfigured = true
        MerianLog.general.debug("PostHog initialized.")
    }

    // MARK: - Identity

    /// Identifies the current user session in PostHog.
    func identifyUser(userId: String) {
        guard isConfigured else {
            MerianLog.general.warning("PostHogManager.identifyUser() called before configure() — identity dropped.")
            return
        }
        PostHogSDK.shared.identify(userId)
        MerianLog.general.debug("PostHog identified user: \(userId, privacy: .private)")
    }

    // MARK: - Session

    /// Resets the PostHog session. Call on sign-out or account deletion.
    func reset() {
        PostHogSDK.shared.reset()
    }
}
