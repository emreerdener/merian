import Testing
import Foundation
import Security
#if canImport(UIKit)
import UIKit
#endif
@testable import Merian

@MainActor
struct DeviceIdentityManagerTests {

    // Helper to brutally purge physical Keychain footprints within the unit test simulator sandbox
    private func wipeTestKeychainBounds() {
        let queryDelete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "Merian_Device_IDFV"
        ]
        SecItemDelete(queryDelete as CFDictionary)
    }

    @Test func testDeviceIdentityExtractsFromHardwareAndPersistsSecurely() {
        // Arrange
        wipeTestKeychainBounds()
        
        let manager = DeviceIdentityManager.shared
        
        // Act: Extract the baseline physical ID natively against empty Keychain bounds
        let extractedDeviceIdentity = manager.getOrGeneratePersistentIDFV()
        
        // Assert
        #expect(extractedDeviceIdentity.isEmpty == false, "Device IDFV MUST natively pull from hardware or generate UUID fallback securely without crashing")
        
        // Act: Pull identity bounds a second time triggering the Keychain fallback sequence natively
        let verificationIdentity = manager.getOrGeneratePersistentIDFV()
        
        // Assert: Ensure exact boundary mapping to prevent ghost RevenueCat/Supabase accounts from duplicating endlessly
        #expect(extractedDeviceIdentity == verificationIdentity, "Keychain bounds failed to securely isolate and map the exact physical device footprint repeatedly")
        
        // Cleanup
        wipeTestKeychainBounds()
    }
}
