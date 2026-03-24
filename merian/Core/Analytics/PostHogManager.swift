import Foundation
import PostHog
import os

// MARK: - Core Telemetry Gateway
/// Handles PostHog anonymous telemetry to track UX funnels, Day-7 retention, and feature abandonment.
@MainActor
final class PostHogManager {
    // MARK: - Singleton Architecture
    static let shared = PostHogManager()
    
    // MARK: - Lifecycle Bootstrapping
    private init() {}
    
    // MARK: - SDK Configuration Phase
    /// Initializes PostHog safely with the API Key mapped from the local configuration.
    func configure() {
        let configuration = PostHogConfig(apiKey: MerianEnvironment.postHogApiKey, host: "https://us.i.posthog.com")
        
        // Auto-track UI boundaries without physical PII stringing
        configuration.captureApplicationLifecycleEvents = true
        // Disabled screen swizzling: PostHog aggressively inserts 'UIKitToolbar' into SwiftUI 'UIHostingController' hierarchies causing iOS 18 strict boundary layout warnings.
        configuration.captureScreenViews = false
        configuration.captureElementInteractions = false
        configuration.sessionReplay = false
        
        PostHogSDK.shared.setup(configuration)
        MerianLog.general.debug("🦔 PostHog securely initialized (Anonymous Funnel Tracking)")
    }
    
    // MARK: - Identity Matrix Binding
    /// Binds the anonymous Supabase Ghost URL uniquely mapping the Day-7 retention graph
    func identifyUser(userId: String) {
        PostHogSDK.shared.identify(userId)
        MerianLog.general.debug("🦔 PostHog bound to Ghost User: \(userId, privacy: .private)")
    }
    
    // MARK: - Security Sandbox Reset
    /// Safely terminates the user boundary when signing out or erasing the profile physically
    func reset() {
        PostHogSDK.shared.reset()
    }
}
