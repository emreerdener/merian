import Foundation

enum MerianEnvironment {
    private enum Keys {
        static let geminiApiKey = "GEMINI_API_KEY"
        static let supabaseUrl = "SUPABASE_URL"
        static let supabaseAnonKey = "SUPABASE_ANON_KEY"
        static let revenueCatApiKey = "REVENUECAT_API_KEY"
        static let postHogApiKey = "POSTHOG_API_KEY"
        static let telemetryAppID = "TELEMETRY_APP_ID"
    }

    private static let infoDictionary: [String: Any] = {
        guard let dict = Bundle.main.infoDictionary else {
            fatalError("Plist file not found")
        }
        return dict
    }()

    static let geminiApiKey: String = {
        guard let string = infoDictionary[Keys.geminiApiKey] as? String else {
            fatalError("Gemini API Key not set in plist")
        }
        return string
    }()

    static let supabaseUrl: String = {
        guard let string = infoDictionary[Keys.supabaseUrl] as? String else {
            fatalError("Supabase URL not set in plist")
        }
        return string
    }()

    static let supabaseAnonKey: String = {
        guard let string = infoDictionary[Keys.supabaseAnonKey] as? String else {
            fatalError("Supabase Anon Key not set in plist")
        }
        return string
    }()

    static let revenueCatApiKey: String = {
        guard let string = infoDictionary[Keys.revenueCatApiKey] as? String else {
            fatalError("RevenueCat API Key not set in plist")
        }
        return string
    }()

    static let postHogApiKey: String = {
        guard let string = infoDictionary[Keys.postHogApiKey] as? String else {
            fatalError("PostHog API Key not set in plist")
        }
        return string
    }()

    static let telemetryAppID: String = {
        guard let string = infoDictionary[Keys.telemetryAppID] as? String else {
            fatalError("Telemetry App ID not set in plist")
        }
        return string
    }()
}