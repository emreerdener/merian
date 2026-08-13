import Foundation
import os
import PostHog

protocol PostHogSDKClient {
    func setup(_ configuration: PostHogConfig)
    func reset()
    func optOut()
    func close()
    func identify(_ userId: String)
    func capture(_ event: String, properties: [String: Any])
    func optIn()
}

struct LivePostHogSDKClient: PostHogSDKClient {
    func setup(_ configuration: PostHogConfig) {
        PostHogSDK.shared.setup(configuration)
    }

    func reset() {
        PostHogSDK.shared.reset()
    }

    func optOut() {
        PostHogSDK.shared.optOut()
    }

    func close() {
        PostHogSDK.shared.close()
    }

    func identify(_ userId: String) {
        PostHogSDK.shared.identify(userId)
    }

    func capture(_ event: String, properties: [String: Any]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    func optIn() {
        PostHogSDK.shared.optIn()
    }
}

/// Device-local transport permission used by PostHog's dedicated URLSession.
/// The application gate remains authoritative; this second gate prevents SDK-
/// originated work such as reset-time feature-flag reloads from reaching the
/// network after permission has closed.
final class PostHogConsentNetworkGate: @unchecked Sendable {
    static let shared = PostHogConsentNetworkGate()
    static let transportHeader = "X-Merian-PostHog-Transport"

    private let lock = NSLock()
    private var transportHosts: [String: String] = [:]
    private var activeTransportId: String?

    var isOpen: Bool {
        lock.withLock { activeTransportId != nil }
    }

    /// Registers one SDK session while leaving it closed. IDs remain known for
    /// the process lifetime so a delayed request from an old session cannot be
    /// admitted when a newer consented session opens.
    func register(host: String) -> String? {
        guard let normalizedHost = SecureTransportPolicy.httpsURL(
            from: host
        )?.host?.lowercased() else {
            return nil
        }
        let transportId = UUID().uuidString
        lock.withLock { transportHosts[transportId] = normalizedHost }
        return transportId
    }

    func open(transportId: String) {
        lock.withLock {
            guard transportHosts[transportId] != nil else { return }
            activeTransportId = transportId
        }
    }

    func close() {
        lock.withLock {
            activeTransportId = nil
        }
    }

    func shouldBlock(_ request: URLRequest) -> Bool {
        guard let requestHost = request.url?.host?.lowercased(),
              let transportId = request.value(
                forHTTPHeaderField: Self.transportHeader
              ) else {
            return false
        }
        return lock.withLock {
            transportHosts[transportId] == requestHost
                && activeTransportId != transportId
        }
    }
}

/// Intercepts denied PostHog requests and completes them locally. It never
/// creates a forwarding task, so blocked payloads cannot leave the device.
final class PostHogConsentURLProtocol: URLProtocol {
    // URLProtocol's Objective-C entry points require class dispatch.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        PostHogConsentNetworkGate.shared.shouldBlock(request)
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {}
}

/// Handles consent-gated, pseudonymous PostHog telemetry for UX funnels,
/// retention, diagnostics, and feature tracking.
/// Not isolated to @MainActor — PostHogSDK is thread-safe and every public
/// operation is protected by the same explicit-permission state.
final class PostHogManager {
    static let shared = PostHogManager()

    private let sdk: PostHogSDKClient
    private let projectToken: () -> String
    private let host: String
    private let shouldBypassSDK: () -> Bool

    init(
        sdk: PostHogSDKClient = LivePostHogSDKClient(),
        projectToken: @escaping () -> String = { MerianEnvironment.postHogApiKey },
        host: String = "https://us.i.posthog.com",
        shouldBypassSDK: @escaping () -> Bool = {
            TestExecutionCoordinator.isRunningTests
        }
    ) {
        self.sdk = sdk
        self.projectToken = projectToken
        self.host = host
        self.shouldBypassSDK = shouldBypassSDK
    }

    private var _isConfigured = false
    private var _isConfiguring = false
    private var _hasConsent = false
    private var permissionGeneration: UInt = 0
    private var configuringGeneration: UInt?
    private var consentedUserId: String?
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
        if shouldBypassSDK() {
            lock.withLock {
                if _hasConsent != granted
                    || granted && consentedUserId != userId {
                    permissionGeneration &+= 1
                }
                _hasConsent = granted
                if !granted {
                    _isConfigured = false
                    _isConfiguring = false
                    configuringGeneration = nil
                    PostHogConsentNetworkGate.shared.close()
                }
                consentedUserId = granted ? userId : nil
                pendingUserId = granted ? userId : nil
            }
            return
        }

        if granted {
            let requiresAccountTransition = lock.withLock {
                _hasConsent
                    && consentedUserId != nil
                    && consentedUserId != userId
            }
            if requiresAccountTransition {
                setConsentGranted(false, userId: nil)
            }

            let activationContext = lock.withLock {
                if !_hasConsent || consentedUserId != userId {
                    permissionGeneration &+= 1
                }
                _hasConsent = true
                consentedUserId = userId
                pendingUserId = userId
                return (
                    generation: permissionGeneration,
                    userId: userId
                )
            }
            configure()
            activateConfiguredSDKIfPermitted(
                generation: activationContext.generation,
                userId: activationContext.userId
            )
            return
        }

        lock.lock()
        permissionGeneration &+= 1
        _hasConsent = false
        consentedUserId = nil
        pendingUserId = nil
        PostHogConsentNetworkGate.shared.close()
        guard _isConfigured else {
            _isConfiguring = false
            configuringGeneration = nil
            lock.unlock()
            return
        }

        // App capture and the SDK's network transport are both closed before
        // reset(). PostHog 3.69.0 reloads feature flags during reset; the
        // dedicated URLProtocol rejects that work locally. reset() clears the
        // prior account, optOut() persists withdrawal, and close() stops SDK
        // integrations and queue activity.
        sdk.reset()
        sdk.optOut()
        sdk.close()

        _isConfigured = false
        _isConfiguring = false
        configuringGeneration = nil
        lock.unlock()
        MerianLog.general.debug("PostHog disabled for the active account.")
    }

    // MARK: - Configuration

    /// Configures the PostHog SDK.
    private func configure() {
        var configurationContext: (generation: UInt, userId: String?)?
        lock.withLock {
            guard _hasConsent, !_isConfigured, !_isConfiguring else { return }
            _isConfiguring = true
            configuringGeneration = permissionGeneration
            configurationContext = (
                generation: permissionGeneration,
                userId: consentedUserId
            )
        }
        guard let configurationContext else { return }

        let projectToken = projectToken()
        guard !projectToken.isEmpty else {
            abandonConfiguration(
                generation: configurationContext.generation
            )
            MerianLog.general.error("PostHog configuration skipped because POSTHOG_API_KEY is missing.")
            return
        }

        let configuration = PostHogConfig(
            projectToken: projectToken,
            host: host
        )

        guard let transportId = PostHogConsentNetworkGate.shared.register(
            host: host
        ) else {
            abandonConfiguration(
                generation: configurationContext.generation
            )
            MerianLog.general.error(
                "PostHog configuration skipped because its host is invalid."
            )
            return
        }

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.protocolClasses = [PostHogConsentURLProtocol.self]
            + (sessionConfiguration.protocolClasses ?? []).filter {
                ObjectIdentifier($0)
                    != ObjectIdentifier(PostHogConsentURLProtocol.self)
            }
        var additionalHeaders = sessionConfiguration.httpAdditionalHeaders
            ?? [:]
        additionalHeaders[PostHogConsentNetworkGate.transportHeader] =
            transportId
        sessionConfiguration.httpAdditionalHeaders = additionalHeaders
        configuration.urlSessionConfiguration = sessionConfiguration

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
        guard _hasConsent,
              permissionGeneration == configurationContext.generation,
              configuringGeneration == configurationContext.generation,
              consentedUserId == configurationContext.userId else {
            if configuringGeneration == configurationContext.generation {
                _isConfiguring = false
                configuringGeneration = nil
            }
            lock.unlock()
            return
        }
        PostHogConsentNetworkGate.shared.open(transportId: transportId)
        sdk.setup(configuration)
        _isConfigured = true
        _isConfiguring = false
        configuringGeneration = nil
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
        sdk.identify(finalUserId)
        lock.unlock()
        MerianLog.general.debug("PostHog identity applied.")
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

        sdk.capture(event, properties: properties)
        lock.unlock()
    }

    /// Serializes SDK activation and identity with revocation. If withdrawal
    /// acquires the lock first, neither call can cross the permission boundary;
    /// if activation is already in progress, withdrawal closes the SDK next.
    private func activateConfiguredSDKIfPermitted(
        generation: UInt,
        userId: String?
    ) {
        var identifiedUserId: String?
        lock.lock()
        guard _hasConsent,
              _isConfigured,
              permissionGeneration == generation,
              consentedUserId == userId else {
            lock.unlock()
            return
        }

        // A previous withdrawal is persisted by the SDK and overrides config
        // during setup. This call is therefore required after a new grant.
        sdk.optIn()
        if let pendingUserId {
            let finalUserId = sdkUserId(pendingUserId)
            sdk.identify(finalUserId)
            identifiedUserId = finalUserId
            self.pendingUserId = nil
        }
        lock.unlock()

        if identifiedUserId != nil {
            MerianLog.general.debug("PostHog identity applied.")
        }
    }

    private func sdkUserId(_ userId: String) -> String {
        #if targetEnvironment(simulator)
        "simulator"
        #else
        userId
        #endif
    }

    private func abandonConfiguration(generation: UInt) {
        lock.withLock {
            guard configuringGeneration == generation else { return }
            _isConfiguring = false
            configuringGeneration = nil
        }
    }
}
