import CryptoKit
import Foundation

#if MERIAN_HISTORY_QUALIFICATION && DEBUG
#error("HistoryQualification must exclude Debug fixtures.")
#endif

enum MerianEnvironment {
    #if MERIAN_HISTORY_QUALIFICATION
    static let isHistoryQualificationBuild = true
    #else
    static let isHistoryQualificationBuild = false
    #endif

    static var allowsAncillaryHostedIntegrations: Bool { !isHistoryQualificationBuild }

    struct HistoryQualificationScope: Sendable, Equatable {
        let approvalID: UUID
        let host: String
        let accountFingerprints: Set<String>
        static let bundleID = "app.merian.Merian"
        static let appGroup = "group.app.merian.shared"
        static let keychainNamespace = "app.merian.shared"
        static let authNamespace = "Merian.HistoryQualification.Auth"
        static let operationScope = "capture-history-v1"

        func permits(accountID: UUID) -> Bool {
            accountFingerprints.contains(Self.fingerprint(accountID))
        }

        static func fingerprint(_ accountID: UUID) -> String {
            let value = "Merian.HistoryQualification.Account/" + accountID.uuidString.lowercased()
            return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    enum HistoryQualificationFailure: Error, Equatable {
        case compiledMarker, approval, target, namespace, operationScope, accounts
    }

    /// Bundled constraints are not deployment or execution authorization. The
    /// operator must separately approve the exact artifact, target and actions.
    static func validateHistoryQualification(info: [String: Any], bundleID: String?,
                                             compiledMarker: Bool) throws -> HistoryQualificationScope {
        guard compiledMarker, info["MERIAN_HISTORY_QUALIFICATION"] as? String == "1" else {
            throw HistoryQualificationFailure.compiledMarker
        }
        guard let approval = info["MERIAN_HISTORY_APPROVAL_ID"] as? String,
              let approvalID = UUID(uuidString: approval), approvalID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw HistoryQualificationFailure.approval
        }
        guard let project = info["MERIAN_HISTORY_APPROVED_PROJECT"] as? String,
              project.range(of: "^[a-z0-9]{20}$", options: .regularExpression) != nil,
              let host = info["MERIAN_HISTORY_APPROVED_HOST"] as? String, host == project + ".supabase.co",
              let rawURL = info["SUPABASE_URL"] as? String, let url = SecureTransportPolicy.httpsURL(from: rawURL),
              url.host == host, url.port == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { throw HistoryQualificationFailure.target }
        guard bundleID == HistoryQualificationScope.bundleID,
              info["MERIAN_APP_GROUP_IDENTIFIER"] as? String == HistoryQualificationScope.appGroup,
              info["MERIAN_KEYCHAIN_NAMESPACE"] as? String == HistoryQualificationScope.keychainNamespace,
              info["MERIAN_AUTH_NAMESPACE"] as? String == HistoryQualificationScope.authNamespace else {
            throw HistoryQualificationFailure.namespace
        }
        guard info["MERIAN_HISTORY_OPERATION_SCOPE"] as? String == HistoryQualificationScope.operationScope else {
            throw HistoryQualificationFailure.operationScope
        }
        guard let rawAccounts = info["MERIAN_HISTORY_ACCOUNT_FINGERPRINTS"] as? String else {
            throw HistoryQualificationFailure.accounts
        }
        let fingerprints = rawAccounts.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard !fingerprints.isEmpty, Set(fingerprints).count == fingerprints.count,
              fingerprints.allSatisfy({ $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }) else {
            throw HistoryQualificationFailure.accounts
        }
        return .init(approvalID: approvalID, host: host, accountFingerprints: Set(fingerprints))
    }

    static let historyQualificationScope = try? validateHistoryQualification(info: Bundle.main.infoDictionary ?? [:],
        bundleID: Bundle.main.bundleIdentifier, compiledMarker: isHistoryQualificationBuild)

    static func requireHistoryQualificationConfiguration() {
        requireHistoryNormalOAuthConfiguration()
        let bundled = Bundle.main.infoDictionary?["MERIAN_HISTORY_QUALIFICATION"] as? String == "1"
        let namespaced = Bundle.main.bundleIdentifier == "app.merian.historyqualification"
        guard (!isHistoryQualificationBuild && !bundled && !namespaced) || historyQualificationScope != nil else {
            fatalError("History qualification configuration is missing or invalid; live clients are unavailable.")
        }
    }

    static func permitsHistoryQualificationAccount(_ accountID: UUID) -> Bool {
        !isHistoryQualificationBuild || historyQualificationScope?.permits(accountID: accountID) == true
    }
    // Existing-account mapping cannot be proven by a local account fingerprint.
    // Keep provider signup/link/callback exchange closed until separately reviewed.
    static func requireQualificationIdentityExchangePermission() throws {
        guard !isHistoryQualificationBuild else { throw HistoryQualificationFailure.accounts }
    }

    static func requireQualificationDeletionPermission() throws {
        guard !isHistoryQualificationBuild else { throw HistoryQualificationFailure.operationScope }
    }

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
                "cleared sessions unless you intend to create a test anonymous user: \(host)."
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

    static let configuration: Configuration = {
        requireHistoryQualificationConfiguration()
        return load()
    }()

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

        let supabaseURL = SecureTransportPolicy.httpsURL(from: supabaseUrl)
        if supabaseURL == nil {
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
            revenueCatApiKey: allowsAncillaryHostedIntegrations ? revenueCatApiKey : "",
            postHogApiKey: allowsAncillaryHostedIntegrations ? postHogApiKey : "",
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
