import Foundation

#if MERIAN_HISTORY_NORMAL_OAUTH && (DEBUG || MERIAN_HISTORY_QUALIFICATION)
#error("History-enabled builds must use normal OAuth without Debug fixtures or qualification Auth.")
#endif

extension MerianEnvironment {
    #if MERIAN_HISTORY_NORMAL_OAUTH
    static let isHistoryNormalOAuthBuild = true
    #else
    static let isHistoryNormalOAuthBuild = false
    #endif

    /// History-enabled builds preserve an existing library on store-open failure.
    static var preservesExistingLibrary: Bool { isHistoryQualificationBuild || isHistoryNormalOAuthBuild }

    static func validatesHistoryNormalOAuthConfiguration(info: [String: Any], bundleID: String?, compiledMarker: Bool) -> Bool {
        guard compiledMarker, info["MERIAN_HISTORY_NORMAL_OAUTH"] as? String == "1",
              info["MERIAN_HISTORY_QUALIFICATION"] as? String != "1",
              bundleID == HistoryQualificationScope.bundleID,
              info["MERIAN_APP_GROUP_IDENTIFIER"] as? String == HistoryQualificationScope.appGroup,
              info["MERIAN_KEYCHAIN_NAMESPACE"] as? String == HistoryQualificationScope.keychainNamespace,
              (info["MERIAN_AUTH_NAMESPACE"] as? String ?? "").isEmpty,
              let rawURL = info["SUPABASE_URL"] as? String,
              let url = SecureTransportPolicy.httpsURL(from: rawURL), url.host == productionSupabaseHost,
              url.port == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return false }
        return true
    }

    static let historyNormalOAuthConfigurationIsValid = validatesHistoryNormalOAuthConfiguration(
        info: Bundle.main.infoDictionary ?? [:], bundleID: Bundle.main.bundleIdentifier, compiledMarker: isHistoryNormalOAuthBuild)

    static func requireHistoryNormalOAuthConfiguration() {
        let bundled = Bundle.main.infoDictionary?["MERIAN_HISTORY_NORMAL_OAUTH"] as? String == "1"
        guard (!isHistoryNormalOAuthBuild && !bundled) || historyNormalOAuthConfigurationIsValid else {
            fatalError("History-enabled normal OAuth configuration is invalid; live clients are unavailable.")
        }
    }
}
