import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
#endif
import Security
import Observation

// MARK: - Core Identity Engine
@MainActor
@Observable final class DeviceIdentityManager {
    // MARK: - Singleton Architecture
    static let shared = DeviceIdentityManager()
    
    private init() {
        self.deviceId = getOrGeneratePersistentIDFV()
    }
    
    // MARK: - Keychain Identifiers
    private let keychainKey = "Merian_Device_IDFV"
    
    // MARK: - State Management
    var deviceId: String = ""
    
    // MARK: - Hardware Fingerprint Generation
    func getOrGeneratePersistentIDFV() -> String {
        let (existingID, status) = loadFromKeychain()
        
        if let existingID = existingID {
            return existingID
        }
        
        // Critical: Protect existing user Identity records from background iOS wiping loops dynamically
        if status == errSecInteractionNotAllowed {
            print("DeviceIdentityManager: Keychain locked in background (errSecInteractionNotAllowed). Throttling execution to protect identities natively.")
            #if canImport(UIKit)
            return UIDevice.current.identifierForVendor?.uuidString ?? ""
            #elseif canImport(WatchKit)
            return WKInterfaceDevice.current().identifierForVendor?.uuidString ?? ""
            #else
            return ""
            #endif
        }
        
        #if canImport(UIKit)
        let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #elseif canImport(WatchKit)
        let newID = WKInterfaceDevice.current().identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let newID = UUID().uuidString
        #endif
        saveToKeychain(value: newID)
        return newID
    }
    
    // MARK: - Native Keychain Persistence
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
    
    private func loadFromKeychain() -> (String?, OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return (String(data: data, encoding: .utf8), status)
        }
        return (nil, status)
    }
}
