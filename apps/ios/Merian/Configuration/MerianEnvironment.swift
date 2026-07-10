import Foundation

enum MerianEnvironment {
    enum ConfigurationIssue: Sendable, Equatable {
        case missingInfoDictionary
        case missingValue(String)
        case invalidSupabaseURL(String)
        case productionSupabaseInDebugSimulator(String)

        var description: String {
            switch self {
            case .missingInfoDictionary:
                return "Info.plist could not be read."
            case .missingValue(let key):
                return "\(key) is missing or empty."
            case .invalidSupabaseURL(let value):
                return "SUPABASE_URL is invalid: \(value)"
            case .productionSupabaseInDebugSimulator(let host):
                return "Debug simulator is using production Supabase; avoid fresh installs or " +
                "cleared sessions unless you intend to create a test ghost user: \(host)."
            }
        }
    }

    struct RuntimeContext: Sendable, Equatable {
        let isDebug: Bool
        let isSimulator: Bool

        static var current: RuntimeContext {
            #if DEBUG
            let isDebug = true
            #else
            let isDebug = false
            #endif

            #if targetEnvironment(simulator)
            let isSimulator = true
            #else
            let isSimulator = false
            #endif

            return RuntimeContext(isDebug: isDebug, isSimulator: isSimulator)
        }
    }

    struct Configuration: Sendable, Equatable {
        let supabaseUrl: String
        let supabaseAnonKey: String
        let revenueCatApiKey: String
        let postHogApiKey: String
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
    }

    static let productionSupabaseHost = "qlarqavoqhkuwzmevrmf.supabase.co"
    static let fallbackSupabaseURL = "https://missing-supabase-config.supabase.co"
    private static let fallbackSupabaseAnonKey = "missing-supabase-anon-key"
    private static let allowProductionSupabaseInDebugSimulatorEnvKey =
        "MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR"

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

    static func load(bundle: Bundle = .main) -> Configuration {
        load(
            infoDictionary: bundle.infoDictionary,
            environment: ProcessInfo.processInfo.environment,
            runtime: .current
        )
    }

    static func load(infoDictionary: [String: Any]?) -> Configuration {
        load(infoDictionary: infoDictionary, environment: [:], runtime: .current)
    }

    static func load(
        infoDictionary: [String: Any]?,
        environment: [String: String],
        runtime: RuntimeContext
    ) -> Configuration {
        guard let infoDictionary else {
            return Configuration(
                supabaseUrl: fallbackSupabaseURL,
                supabaseAnonKey: fallbackSupabaseAnonKey,
                revenueCatApiKey: "",
                postHogApiKey: "",
                issues: [
                    .missingInfoDictionary,
                    .missingValue(Keys.supabaseUrl),
                    .missingValue(Keys.supabaseAnonKey),
                    .missingValue(Keys.revenueCatApiKey),
                    .missingValue(Keys.postHogApiKey)
                ]
            )
        }

        var issues: [ConfigurationIssue] = []

        let supabaseUrl = value(for: Keys.supabaseUrl, in: infoDictionary, issues: &issues) ?? fallbackSupabaseURL
        let supabaseAnonKey = value(for: Keys.supabaseAnonKey, in: infoDictionary, issues: &issues) ?? fallbackSupabaseAnonKey
        let revenueCatApiKey = value(for: Keys.revenueCatApiKey, in: infoDictionary, issues: &issues) ?? ""
        let postHogApiKey = value(for: Keys.postHogApiKey, in: infoDictionary, issues: &issues) ?? ""

        let supabaseURL = URL(string: supabaseUrl)
        if supabaseURL?.scheme == nil || supabaseURL?.host == nil {
            issues.append(.invalidSupabaseURL(supabaseUrl))
        }

        if shouldWarnProductionSupabase(
            url: supabaseURL,
            environment: environment,
            runtime: runtime
        ) {
            issues.append(.productionSupabaseInDebugSimulator(productionSupabaseHost))
        }

        return Configuration(
            supabaseUrl: issues.contains(where: {
                if case .invalidSupabaseURL = $0 { return true }
                return false
            }) ? fallbackSupabaseURL : supabaseUrl,
            supabaseAnonKey: supabaseAnonKey,
            revenueCatApiKey: revenueCatApiKey,
            postHogApiKey: postHogApiKey,
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

    private static func shouldWarnProductionSupabase(
        url: URL?,
        environment: [String: String],
        runtime: RuntimeContext
    ) -> Bool {
        guard runtime.isDebug, runtime.isSimulator else { return false }
        guard url?.host?.lowercased() == productionSupabaseHost else { return false }
        return !isTruthy(environment[allowProductionSupabaseInDebugSimulatorEnvKey])
    }

    private static func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }
}
