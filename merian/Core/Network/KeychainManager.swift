import Foundation
import Security
import os

// MARK: - Keychain Manager

/// Thin wrapper around Security framework keychain operations.
/// Used for storing sensitive boolean flags (e.g., OAuth authentication state)
/// that must survive app deletion and be device-specific.
final class KeychainManager {
    static let shared = KeychainManager()

    private init() {
        migrateFromUserDefaults()
    }

    // MARK: - Public Interface

    func set(_ value: Bool, forKey key: String) {
        let data = Data([value ? 1 : 0])

        // Delete before add to avoid duplicate-item errors.
        SecItemDelete(baseQuery(for: key) as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func bool(forKey key: String) -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data, let firstByte = data.first else {
            return false
        }
        return firstByte == 1
    }

    func removeObject(forKey key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    // MARK: - Private Helpers

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
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
