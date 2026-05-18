import Foundation
import Security

enum ShareImportAuthError: LocalizedError {
    case missingSharedSession
    case expiredSession
    case invalidSupabaseConfiguration
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .missingSharedSession:
            return "Open Merian once to finish setup, then try sharing again."
        case .expiredSession:
            return "Open Merian to refresh your session, then try sharing again."
        case .invalidSupabaseConfiguration:
            return "Merian is missing its upload configuration."
        case .refreshFailed:
            return "Merian could not refresh your session. Open the app and try again."
        }
    }
}

struct ShareImportStoredSession: Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: TimeInterval?
    let userId: String?
    let rootJSONObject: [String: Any]
    let isWrappedSession: Bool

    static func == (lhs: ShareImportStoredSession, rhs: ShareImportStoredSession) -> Bool {
        lhs.accessToken == rhs.accessToken &&
        lhs.refreshToken == rhs.refreshToken &&
        lhs.expiresAt == rhs.expiresAt &&
        lhs.userId == rhs.userId &&
        lhs.isWrappedSession == rhs.isWrappedSession
    }

    var isExpired: Bool {
        guard let expiresAt else {
            return ShareImportAuthStore.jwtExpiration(accessToken).map {
                $0.timeIntervalSinceNow < ShareImportSharedConstants.authExpiryRefreshMargin
            } ?? true
        }
        return Date(timeIntervalSince1970: expiresAt).timeIntervalSinceNow < ShareImportSharedConstants.authExpiryRefreshMargin
    }
}

struct ShareImportKeychainSessionStore {
    let service: String
    let account: String
    let accessGroup: String?

    init(
        service: String = ShareImportSharedConstants.supabaseKeychainService,
        account: String,
        accessGroup: String?
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    func read() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    func write(_ data: Data) throws {
        let query = baseQuery
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        var addAttributes = query
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

enum ShareImportAuthStore {
    static func keychainAccessGroup(bundle: Bundle = .main) -> String? {
        guard let rawPrefix = bundle.object(forInfoDictionaryKey: ShareImportSharedConstants.appIdentifierPrefixInfoKey) as? String else {
            return nil
        }

        let prefix = rawPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, !prefix.contains("$(") else { return nil }
        return "\(prefix)\(ShareImportSharedConstants.keychainAccessGroupSuffix)"
    }

    static func supabaseStorageKey(supabaseURLString: String = MerianEnvironment.supabaseUrl) -> String {
        guard let host = URL(string: supabaseURLString)?.host,
              let projectRef = host.split(separator: ".").first else {
            return "supabase.auth.token"
        }
        return "sb-\(projectRef)-auth-token"
    }

    static func readSharedSession() throws -> ShareImportStoredSession {
        let store = ShareImportKeychainSessionStore(
            account: supabaseStorageKey(),
            accessGroup: keychainAccessGroup()
        )
        guard let data = store.read(),
              let session = parseSessionData(data) else {
            throw ShareImportAuthError.missingSharedSession
        }
        return session
    }

    static func validAccessToken() async throws -> String {
        let session = try readSharedSession()
        guard !session.isExpired else {
            guard let refreshed = try await refresh(session: session) else {
                throw ShareImportAuthError.expiredSession
            }
            return refreshed.accessToken
        }
        return session.accessToken
    }

    @discardableResult
    static func migrateLegacySessionToSharedIfNeeded() -> Bool {
        let account = supabaseStorageKey()
        let sharedStore = ShareImportKeychainSessionStore(
            account: account,
            accessGroup: keychainAccessGroup()
        )

        if let sharedData = sharedStore.read(), parseSessionData(sharedData) != nil {
            return false
        }

        let legacyStore = ShareImportKeychainSessionStore(account: account, accessGroup: nil)
        guard let legacyData = legacyStore.read(),
              migratedSessionData(legacyData: legacyData, sharedData: nil) != nil else {
            return false
        }

        do {
            try sharedStore.write(legacyData)
            return true
        } catch {
            return false
        }
    }

    static func migratedSessionData(legacyData: Data?, sharedData: Data?) -> Data? {
        guard sharedData.flatMap(parseSessionData) == nil,
              let legacyData,
              parseSessionData(legacyData) != nil else {
            return nil
        }
        return legacyData
    }

    static func parseSessionData(_ data: Data) -> ShareImportStoredSession? {
        guard let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let isWrapped = rootObject["session"] is [String: Any]
        let sessionObject = (rootObject["session"] as? [String: Any]) ?? rootObject

        guard let accessToken = stringValue(in: sessionObject, keys: ["accessToken", "access_token"]),
              !accessToken.isEmpty else {
            return nil
        }

        let user = sessionObject["user"] as? [String: Any]
        return ShareImportStoredSession(
            accessToken: accessToken,
            refreshToken: stringValue(in: sessionObject, keys: ["refreshToken", "refresh_token"]),
            expiresAt: doubleValue(in: sessionObject, keys: ["expiresAt", "expires_at"]) ??
                jwtExpiration(accessToken)?.timeIntervalSince1970,
            userId: stringValue(in: user ?? [:], keys: ["id"]),
            rootJSONObject: rootObject,
            isWrappedSession: isWrapped
        )
    }

    static func jwtExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = doubleValue(in: object, keys: ["exp"]) else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private static func refresh(session: ShareImportStoredSession) async throws -> ShareImportStoredSession? {
        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            return nil
        }
        guard let url = URL(string: "\(MerianEnvironment.supabaseUrl)/auth/v1/token?grant_type=refresh_token"),
              MerianEnvironment.isSupabaseConfigured else {
            throw ShareImportAuthError.invalidSupabaseConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(MerianEnvironment.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let refreshObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = stringValue(in: refreshObject, keys: ["access_token", "accessToken"]) else {
            throw ShareImportAuthError.refreshFailed
        }

        var sessionObject = (session.rootJSONObject["session"] as? [String: Any]) ?? session.rootJSONObject
        sessionObject["accessToken"] = accessToken
        sessionObject["tokenType"] = stringValue(in: refreshObject, keys: ["token_type", "tokenType"]) ?? "bearer"
        sessionObject["expiresIn"] = doubleValue(in: refreshObject, keys: ["expires_in", "expiresIn"]) ?? 3_600
        sessionObject["expiresAt"] = doubleValue(in: refreshObject, keys: ["expires_at", "expiresAt"]) ??
            Date().addingTimeInterval(sessionObject["expiresIn"] as? TimeInterval ?? 3_600).timeIntervalSince1970
        sessionObject["refreshToken"] = stringValue(in: refreshObject, keys: ["refresh_token", "refreshToken"]) ?? refreshToken

        var rootObject = session.rootJSONObject
        if session.isWrappedSession {
            rootObject["session"] = sessionObject
        } else {
            rootObject = sessionObject
        }

        let encoded = try JSONSerialization.data(withJSONObject: rootObject)
        let store = ShareImportKeychainSessionStore(
            account: supabaseStorageKey(),
            accessGroup: keychainAccessGroup()
        )
        try store.write(encoded)
        return parseSessionData(encoded)
    }

    private static func stringValue(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                return value
            }
        }
        return nil
    }

    private static func doubleValue(in object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double {
                return value
            }
            if let value = object[key] as? Int {
                return Double(value)
            }
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }
}
