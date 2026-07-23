import Foundation
import os
import Security

// MARK: - Keychain Manager

/// Thin wrapper around Security framework keychain operations.
/// Used for storing sensitive device-bound state (for example OAuth status and
/// account-upgrade proofs) that must survive app deletion.
final class KeychainManager {
    enum Accessibility {
        case afterFirstUnlockThisDeviceOnly
        case whenUnlockedThisDeviceOnly

        fileprivate var securityValue: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenUnlockedThisDeviceOnly:
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        }
    }

    static let shared = KeychainManager()
    private static let testStorePrefix = "merian.keychain.test."

    private init() {
        migrateFromUserDefaults()
    }

    // MARK: - Public Interface

    @discardableResult
    func set(_ value: Bool, forKey key: String) -> Bool {
        set(Data([value ? 1 : 0]), forKey: key)
    }

    func bool(forKey key: String) -> Bool {
        data(forKey: key)?.first == 1
    }

    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        set(Data(value.utf8), forKey: key)
    }

    func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func set(
        _ data: Data,
        forKey key: String,
        accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly
    ) -> Bool {
        if shouldUseTestStore {
            UserDefaults.standard.set(data, forKey: testStoreKey(for: key))
            return UserDefaults.standard.data(forKey: testStoreKey(for: key)) == data
        }

        let status = upsertKeychainData(
            data,
            forKey: key,
            accessibility: accessibility
        )
        if status != errSecSuccess {
            MerianLog.network.error("Keychain write failed for \(key, privacy: .private): \(status, privacy: .public)")
        }
        return status == errSecSuccess
    }

    func data(forKey key: String) -> Data? {
        if shouldUseTestStore {
            return UserDefaults.standard.data(forKey: testStoreKey(for: key))
        }

        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess {
            return item as? Data
        }

        if status != errSecItemNotFound {
            MerianLog.network.error("Keychain read failed for \(key, privacy: .private): \(status, privacy: .public)")
        }

        return nil
    }

    func removeObject(forKey key: String) {
        if shouldUseTestStore {
            clearTestValue(forKey: key)
            return
        }

        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            MerianLog.network.error("Keychain delete failed for \(key, privacy: .private): \(status, privacy: .public)")
        }
    }

    // MARK: - Private Helpers

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
    }

    private var serviceName: String {
        Bundle.main.bundleIdentifier ?? "app.merian.Merian"
    }

    @discardableResult
    private func upsertKeychainData(
        _ data: Data,
        forKey key: String,
        accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly
    ) -> OSStatus {
        let query = baseQuery(for: key)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.securityValue
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return errSecSuccess
        }

        guard updateStatus == errSecItemNotFound else {
            return updateStatus
        }

        var addAttributes = query
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = accessibility.securityValue
        return SecItemAdd(addAttributes as CFDictionary, nil)
    }

    private var shouldUseTestStore: Bool {
        TestExecutionCoordinator.isRunningTests
    }

    private func testStoreKey(for key: String) -> String {
        Self.testStorePrefix + key
    }

    private func clearTestValue(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: testStoreKey(for: key))
    }

    /// One-time migration of legacy auth flags from UserDefaults to Keychain.
    private func migrateFromUserDefaults() {
        let legacyKey = KeychainKeys.hasAuthenticatedOAuth
        if let legacyValue = UserDefaults.standard.object(forKey: legacyKey) as? Bool {
            self.set(legacyValue, forKey: legacyKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            MerianLog.network.debug("Migrated legacy auth flag from UserDefaults to Keychain.")
        }
    }
}
