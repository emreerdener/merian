import Foundation

enum MerianEnvironment {
    enum ConfigurationIssue: Sendable, Equatable {
        case missingInfoDictionary
        case missingValue(String)
        case invalidSupabaseURL(String)

        var description: String {
            switch self {
            case .missingInfoDictionary:
                return "Info.plist could not be read."
            case .missingValue(let key):
                return "\(key) is missing or empty."
            case .invalidSupabaseURL(let value):
                return "SUPABASE_URL is invalid: \(value)"
            }
        }
    }

    struct Configuration: Sendable, Equatable {
        let supabaseUrl: String
        let supabaseAnonKey: String
        let revenueCatApiKey: String
        let postHogApiKey: String
        let telemetryAppID: String
        let issues: [ConfigurationIssue]

        var hasSupabaseConfiguration: Bool {
            !issues.contains(.missingValue(Keys.supabaseUrl)) &&
            !issues.contains(.missingValue(Keys.supabaseAnonKey)) &&
            issues.allSatisfy {
                if case .invalidSupabaseURL = $0 { return false }
                return true
            }
        }
    }

    private enum Keys {
        static let supabaseUrl = "SUPABASE_URL"
        static let supabaseAnonKey = "SUPABASE_ANON_KEY"
        static let revenueCatApiKey = "REVENUECAT_API_KEY"
        static let postHogApiKey = "POSTHOG_API_KEY"
        static let telemetryAppID = "TELEMETRY_APP_ID"
    }

    static let fallbackSupabaseURL = "https://missing-supabase-config.supabase.co"
    private static let fallbackSupabaseAnonKey = "missing-supabase-anon-key"

    static let configuration = load()

    static var configurationIssues: [ConfigurationIssue] {
        configuration.issues
    }

    static var isSupabaseConfigured: Bool {
        configuration.hasSupabaseConfiguration
    }

    static var supabaseUrl: String { configuration.supabaseUrl }
    static var supabaseAnonKey: String { configuration.supabaseAnonKey }
    static var revenueCatApiKey: String { configuration.revenueCatApiKey }
    static var postHogApiKey: String { configuration.postHogApiKey }
    static var telemetryAppID: String { configuration.telemetryAppID }

    static func load(bundle: Bundle = .main) -> Configuration {
        load(infoDictionary: bundle.infoDictionary)
    }

    static func load(infoDictionary: [String: Any]?) -> Configuration {
        guard let infoDictionary else {
            return Configuration(
                supabaseUrl: fallbackSupabaseURL,
                supabaseAnonKey: fallbackSupabaseAnonKey,
                revenueCatApiKey: "",
                postHogApiKey: "",
                telemetryAppID: "",
                issues: [
                    .missingInfoDictionary,
                    .missingValue(Keys.supabaseUrl),
                    .missingValue(Keys.supabaseAnonKey),
                    .missingValue(Keys.revenueCatApiKey),
                    .missingValue(Keys.postHogApiKey),
                    .missingValue(Keys.telemetryAppID)
                ]
            )
        }

        var issues: [ConfigurationIssue] = []

        let supabaseUrl = value(for: Keys.supabaseUrl, in: infoDictionary, issues: &issues) ?? fallbackSupabaseURL
        let supabaseAnonKey = value(for: Keys.supabaseAnonKey, in: infoDictionary, issues: &issues) ?? fallbackSupabaseAnonKey
        let revenueCatApiKey = value(for: Keys.revenueCatApiKey, in: infoDictionary, issues: &issues) ?? ""
        let postHogApiKey = value(for: Keys.postHogApiKey, in: infoDictionary, issues: &issues) ?? ""
        let telemetryAppID = value(for: Keys.telemetryAppID, in: infoDictionary, issues: &issues) ?? ""

        if URL(string: supabaseUrl)?.scheme == nil || URL(string: supabaseUrl)?.host == nil {
            issues.append(.invalidSupabaseURL(supabaseUrl))
        }

        return Configuration(
            supabaseUrl: issues.contains(where: {
                if case .invalidSupabaseURL = $0 { return true }
                return false
            }) ? fallbackSupabaseURL : supabaseUrl,
            supabaseAnonKey: supabaseAnonKey,
            revenueCatApiKey: revenueCatApiKey,
            postHogApiKey: postHogApiKey,
            telemetryAppID: telemetryAppID,
            issues: issues
        )
    }

    private static func value(
        for key: String,
        in infoDictionary: [String: Any],
        issues: inout [ConfigurationIssue]
    ) -> String? {
        guard let string = infoDictionary[key] as? String else {
            issues.append(.missingValue(key))
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            issues.append(.missingValue(key))
            return nil
        }

        return trimmed
    }
}
