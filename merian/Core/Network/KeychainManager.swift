import Foundation
import Security
import os

final class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {
        let legacyKey = "Merian_HasAuthenticatedOAuth"
        if let legacyValue = UserDefaults.standard.object(forKey: legacyKey) as? Bool {
            self.set(legacyValue, forKey: legacyKey)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            MerianLog.network.debug("🔐 Securely migrated legacy auth flag to Keychain")
        }
    }
    
    func set(_ value: Bool, forKey key: String) {
        let boolData = Data([value ? 1 : 0])
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        // Remove existing item to avoid duplicate errors
        SecItemDelete(query as CFDictionary)
        
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: boolData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        SecItemAdd(attributes as CFDictionary, nil)
    }
    
    func bool(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess, let data = item as? Data, let firstByte = data.first {
            return firstByte == 1
        }
        
        return false
    }
    
    func removeObject(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
