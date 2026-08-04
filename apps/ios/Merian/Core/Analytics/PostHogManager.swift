import Foundation
import os
import PostHog

/// Handles consent-gated, pseudonymous PostHog telemetry for UX funnels,
/// retention, diagnostics, and feature tracking.
/// Not isolated to @MainActor — PostHogSDK is thread-safe and every public
/// operation is protected by the same explicit-permission state.
final class PostHogManager {
    static let shared = PostHogManager()
    private init() {}

    private var _isConfigured = false
    private var _isConfiguring = false
    private var _hasConsent = false
    private var pendingUserId: String?
    private let lock = NSLock()

    var isConfigured: Bool {
        lock.withLock { _isConfigured }
    }

    var isCaptureEnabled: Bool {
        lock.withLock { _hasConsent && _isConfigured }
    }

    var hasConsent: Bool {
        lock.withLock { _hasConsent }
    }

    // MARK: - Permission

    /// Applies the durable permission state for the active Supabase account.
    /// A false value is also used during account transitions while the next
    /// account's cloud event stream is unresolved.
    func setConsentGranted(_ granted: Bool, userId: String?) {
        if TestExecutionCoordinator.isRunningTests {
            lock.withLock {
                _hasConsent = granted
                if !granted {
                    _isConfigured = false
                    _isConfiguring = false
                }
                pendingUserId = granted ? userId : nil
            }
            return
        }

        if granted {
            lock.withLock {
                _hasConsent = true
                pendingUserId = userId
            }
            configure()
            activateConfiguredSDKIfPermitted()
            return
        }

        lock.lock()
        _hasConsent = false
        pendingUserId = nil
        guard _isConfigured else {
            lock.unlock()
            return
        }

        // Stop app-originated capture before touching SDK identity. reset()
        // clears the prior account; optOut() persists the withdrawn state; and
        // close() stops lifecycle integrations and queue activity.
        PostHogSDK.shared.reset()
        PostHogSDK.shared.optOut()
        PostHogSDK.shared.close()

        _isConfigured = false
        _isConfiguring = false
        lock.unlock()
        MerianLog.general.debug("PostHog disabled for the active account.")
    }

    // MARK: - Configuration

    /// Configures the PostHog SDK.
    private func configure() {
        var shouldConfigure = false
        lock.withLock {
            guard _hasConsent, !_isConfigured, !_isConfiguring else { return }
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
            projectToken: MerianEnvironment.postHogApiKey,
            host: "https://us.i.posthog.com"
        )

        // Track lifecycle events but keep swizzling-based UI integrations off.
        // PostHog's screen, replay, survey, and autocapture hooks subscribe to layout
        // changes and can insert UIKit helper views into SwiftUI hosting hierarchies.
        configuration.captureApplicationLifecycleEvents = true
        configuration.captureScreenViews = false
        configuration.captureElementInteractions = false
        configuration.sessionReplay = false
        configuration.surveys = false
        configuration.enableSwizzling = false
        configuration.capturePushNotificationSubscriptions = false
        configuration.capturePushNotificationOpened = false

        lock.lock()
        guard _hasConsent else {
            _isConfiguring = false
            lock.unlock()
            return
        }
        PostHogSDK.shared.setup(configuration)
        _isConfigured = true
        _isConfiguring = false
        lock.unlock()

        MerianLog.general.debug("PostHog initialized.")
    }

    // MARK: - Identity

    /// Identifies the current user session in PostHog.
    func identifyUser(userId: String) {
        lock.lock()
        guard _hasConsent else {
            lock.unlock()
            MerianLog.general.debug("PostHog identity dropped because analytics permission is off.")
            return
        }
        guard _isConfigured else {
            MerianLog.general.debug("PostHog identity buffered while consented SDK configuration completes.")
            pendingUserId = userId
            lock.unlock()
            return
        }
        let finalUserId = sdkUserId(userId)
        PostHogSDK.shared.identify(finalUserId)
        lock.unlock()
        MerianLog.general.debug("PostHog identified user: \(finalUserId, privacy: .private)")
    }

    // MARK: - Session

    /// Disables PostHog for the current session. The durable account permission
    /// manager may enable it again after the next auth identity resolves.
    func reset() {
        setConsentGranted(false, userId: nil)
    }

    // MARK: - Events

    func capture(_ event: String, properties: [String: Any] = [:]) {
        lock.lock()
        guard _hasConsent && _isConfigured else {
            lock.unlock()
            MerianLog.general.debug("PostHog event dropped because analytics permission is off: \(event, privacy: .public)")
            return
        }

        PostHogSDK.shared.capture(event, properties: properties)
        lock.unlock()
    }

    /// Serializes SDK activation and identity with revocation. If withdrawal
    /// acquires the lock first, neither call can cross the permission boundary;
    /// if activation is already in progress, withdrawal closes the SDK next.
    private func activateConfiguredSDKIfPermitted() {
        var identifiedUserId: String?
        lock.lock()
        guard _hasConsent && _isConfigured else {
            lock.unlock()
            return
        }

        // A previous withdrawal is persisted by the SDK and overrides config
        // during setup. This call is therefore required after a new grant.
        PostHogSDK.shared.optIn()
        if let pendingUserId {
            let finalUserId = sdkUserId(pendingUserId)
            PostHogSDK.shared.identify(finalUserId)
            identifiedUserId = finalUserId
            self.pendingUserId = nil
        }
        lock.unlock()

        if let identifiedUserId {
            MerianLog.general.debug(
                "PostHog identified user: \(identifiedUserId, privacy: .private)"
            )
        }
    }

    private func sdkUserId(_ userId: String) -> String {
        #if targetEnvironment(simulator)
        "simulator"
        #else
        userId
        #endif
    }
}
