import Foundation
import PostHog

/// Handles PostHog anonymous telemetry to track UX funnels, Day-7 retention, and feature abandonment.
@MainActor
final class PostHogManager {
    static let shared = PostHogManager()
    
    private init() {}
    
    /// Initializes PostHog safely with the API Key mapped from the local configuration.
    func configure() {
        let configuration = PostHogConfig(apiKey: MerianEnvironment.postHogApiKey, host: "https://us.i.posthog.com")
        
        // Auto-track UI boundaries without physical PII stringing
        configuration.captureApplicationLifecycleEvents = true
        configuration.captureScreenViews = true
        
        PostHogSDK.shared.setup(configuration)
        print("🦔 PostHog securely initialized (Anonymous Funnel Tracking)")
    }
    
    /// Binds the anonymous Supabase Ghost URL uniquely mapping the Day-7 retention graph
    func identifyUser(userId: String) {
        PostHogSDK.shared.identify(userId)
        print("🦔 PostHog bound to Ghost User: \(userId)")
    }
    
    /// Safely terminates the user boundary when signing out or erasing the profile physically
    func reset() {
        PostHogSDK.shared.reset()
    }
}
