import Foundation
import os
import Security

// MARK: - Keychain Manager

/// Thin wrapper around Security framework keychain operations.
/// Used for storing sensitive boolean flags (e.g., OAuth authentication state)
/// that must survive app deletion and be device-specific.
final class KeychainManager {
    static let shared = KeychainManager()
    private static let testStorePrefix = "merian.keychain.test."

    private init() {
        migrateFromUserDefaults()
    }

    // MARK: - Public Interface

    func set(_ value: Bool, forKey key: String) {
        if shouldUseTestStore {
            writeTestValue(value, forKey: key)
            return
        }

        let data = Data([value ? 1 : 0])
        let status = upsertKeychainData(data, forKey: key)
        if status != errSecSuccess {
            MerianLog.network.error("Keychain write failed for \(key, privacy: .private): \(status, privacy: .public)")
        }
    }

    func bool(forKey key: String) -> Bool {
        if shouldUseTestStore {
            return readTestValue(forKey: key) ?? false
        }

        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data, let firstByte = data.first {
            return firstByte == 1
        }

        if status != errSecItemNotFound {
            MerianLog.network.error("Keychain read failed for \(key, privacy: .private): \(status, privacy: .public)")
        }

        return false
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
    private func upsertKeychainData(_ data: Data, forKey key: String) -> OSStatus {
        let query = baseQuery(for: key)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
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
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addAttributes as CFDictionary, nil)
    }

    private var shouldUseTestStore: Bool {
        TestExecutionCoordinator.isRunningTests
    }

    private func testStoreKey(for key: String) -> String {
        Self.testStorePrefix + key
    }

    private func writeTestValue(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: testStoreKey(for: key))
    }

    private func readTestValue(forKey key: String) -> Bool? {
        let key = testStoreKey(for: key)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func clearTestValue(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: testStoreKey(for: key))
    }

    /// One-time migration of legacy auth flags from UserDefaults to Keychain.
    private func migrateFromUserDefaults() {
        let legacyKey = "Merian_HasAuthenticatedOAuth"
        if let legacyValue = UserDefaults.standard.object(forKey: legacyKey) as? Bool {
            self.set(legacyValue, forKey: legacyKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            MerianLog.network.debug("Migrated legacy auth flag from UserDefaults to Keychain.")
        }
    }
}
