import Foundation
import UIKit
import Security

@MainActor
final class DeviceIdentityManager: ObservableObject {
    static let shared = DeviceIdentityManager()
    
    private let keychainKey = "Merian_Device_IDFV"
    
    @Published var deviceId: String = ""
    
    private init() {
        self.deviceId = getOrGeneratePersistentIDFV()
    }
    
    func getOrGeneratePersistentIDFV() -> String {
        if let existingID = loadFromKeychain() {
            return existingID
        }
        
        let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        saveToKeychain(value: newID)
        return newID
    }
    
    private func saveToKeychain(value: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        // Remove existing item if any
        let queryDelete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(queryDelete as CFDictionary)
        
        let queryAdd: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        SecItemAdd(queryAdd as CFDictionary, nil)
    }
    
    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
