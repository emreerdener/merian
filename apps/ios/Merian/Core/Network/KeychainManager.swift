import Foundation
import os
import Security

// MARK: - Keychain Manager

/// Thin wrapper around Security framework keychain operations.
/// Used for storing sensitive device-bound state (for example OAuth status and
/// account-upgrade proofs) that must survive app deletion.
final class KeychainManager {
    enum AccessError: LocalizedError {
        case unexpectedItemType
        case unexpectedStatus(OSStatus)
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .unexpectedItemType:
                return "The Keychain item did not contain data."
            case let .unexpectedStatus(status):
                return "Keychain access failed with status \(status)."
            case .verificationFailed:
                return "The Keychain mutation could not be verified."
            }
        }
    }

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
        do {
            return try dataOrThrow(forKey: key)
        } catch {
            MerianLog.network.error(
                "Keychain read failed for \(key, privacy: .private): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Reads while preserving `errSecItemNotFound` versus an actual Keychain
    /// failure. Durable state machines must use this API so uncertainty cannot
    /// be mistaken for absence.
    func dataOrThrow(forKey key: String) throws -> Data? {
        if shouldUseTestStore {
            return UserDefaults.standard.data(forKey: testStoreKey(for: key))
        }

        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw AccessError.unexpectedItemType
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw AccessError.unexpectedStatus(status)
        }
    }

    func removeObject(forKey key: String) {
        do {
            try removeObjectVerified(forKey: key)
        } catch {
            MerianLog.network.error(
                "Keychain delete failed for \(key, privacy: .private): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Deletes and verifies absence while preserving Security.framework error
    /// status. This prevents a failed verification read from looking like a
    /// successful deletion.
    func removeObjectVerified(forKey key: String) throws {
        if shouldUseTestStore {
            clearTestValue(forKey: key)
            guard UserDefaults.standard.data(
                forKey: testStoreKey(for: key)
            ) == nil else {
                throw AccessError.verificationFailed
            }
            return
        }

        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AccessError.unexpectedStatus(status)
        }
        guard try dataOrThrow(forKey: key) == nil else {
            throw AccessError.verificationFailed
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
