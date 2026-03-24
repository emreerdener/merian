import Foundation
import PostHog
import os

/// Handles PostHog anonymous telemetry for UX funnels, retention, and feature tracking.
@MainActor
final class PostHogManager {
    static let shared = PostHogManager()
    private init() {}

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
        MerianLog.general.debug("PostHog initialized.")
    }

    // MARK: - Identity

    /// Identifies the current user session in PostHog.
    func identifyUser(userId: String) {
        PostHogSDK.shared.identify(userId)
        MerianLog.general.debug("PostHog identified user: \(userId, privacy: .private)")
    }

    // MARK: - Session

    /// Resets the PostHog session. Call on sign-out or account deletion.
    func reset() {
        PostHogSDK.shared.reset()
    }
}
