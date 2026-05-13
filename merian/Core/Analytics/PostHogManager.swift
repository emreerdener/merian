import Foundation
import os
import PostHog

/// Handles PostHog anonymous telemetry for UX funnels, retention, and feature tracking.
/// Not isolated to @MainActor — PostHogSDK is thread-safe and configure() runs on a
/// background thread via Task.detached in MerianApp.init().
final class PostHogManager {
    static let shared = PostHogManager()
    private init() {}

    private var _isConfigured = false
    private var _isConfiguring = false
    private var pendingUserId: String?
    private let lock = NSLock()

    var isConfigured: Bool {
        lock.withLock { _isConfigured }
    }

    // MARK: - Configuration

    /// Configures the PostHog SDK.
    func configure() {
        var shouldConfigure = false
        lock.withLock {
            guard !_isConfigured, !_isConfiguring else { return }
            _isConfiguring = true
            shouldConfigure = true
        }
        guard shouldConfigure else { return }

        guard !MerianEnvironment.postHogApiKey.isEmpty else {
            lock.withLock { _isConfiguring = false }
            MerianLog.general.error("PostHog configuration skipped because POSTHOG_API_KEY is missing.")
            return
        }

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
        
        var pendingId: String?
        lock.withLock {
            _isConfigured = true
            _isConfiguring = false
            pendingId = pendingUserId
            pendingUserId = nil
        }
        
        MerianLog.general.debug("PostHog initialized.")
        
        if let idToIdentify = pendingId {
            identifyUser(userId: idToIdentify)
        }
    }

    // MARK: - Identity

    /// Identifies the current user session in PostHog.
    func identifyUser(userId: String) {
        lock.lock()
        guard _isConfigured else {
            MerianLog.general.debug("PostHog identity buffered until SDK configuration completes.")
            pendingUserId = userId
            lock.unlock()
            return
        }
        lock.unlock()

        #if targetEnvironment(simulator)
        let finalUserId = "simulator"
        #else
        let finalUserId = userId
        #endif

        PostHogSDK.shared.identify(finalUserId)
        MerianLog.general.debug("PostHog identified user: \(finalUserId, privacy: .private)")
    }

    // MARK: - Session

    /// Resets the PostHog session. Call on sign-out or account deletion.
    func reset() {
        PostHogSDK.shared.reset()
    }
}
