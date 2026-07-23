import Foundation
@testable import Merian
import Testing

@Suite("Keychain Manager Tests", .serialized) // Serialized because Keychain runs across shared system process
struct KeychainManagerTests {
    
    // Use an ephemeral UUID-based key so we don't accidentally blow away real stored auth credentials if run on host device
    let testKey = "merian_unit_test_\(UUID().uuidString)"
    
    @Test func testBooleanPersistenceSucceeds() async {
        // Arrange
        let manager = KeychainManager.shared
        
        // Ensure starting clean
        manager.removeObject(forKey: testKey)
        #expect(manager.bool(forKey: testKey) == false)
        
        // Act: Save True
        manager.set(true, forKey: testKey)
        
        // Assert: Reads True
        #expect(manager.bool(forKey: testKey) == true)
        
        // Act: Overwrite False
        manager.set(false, forKey: testKey)
        
        // Assert: Reads False
        #expect(manager.bool(forKey: testKey) == false)
        
        // Teardown
        manager.removeObject(forKey: testKey)
    }
    
    @Test func testRemovalDestroysObjectGlobally() async {
        let manager = KeychainManager.shared
        
        manager.set(true, forKey: testKey)
        #expect(manager.bool(forKey: testKey) == true)
        
        manager.removeObject(forKey: testKey)
        #expect(manager.bool(forKey: testKey) == false)
    }
    
    @Test func testFetchingGhostKeyReturnsFalseGracefully() async {
        let manager = KeychainManager.shared
        // `testKey` was never set
        #expect(manager.bool(forKey: testKey + "_ghost") == false)
    }

    @Test func testSensitiveDataRoundTripsAndCanBeRemoved() async {
        let manager = KeychainManager.shared
        let key = testKey + "_data"
        let value = Data((0..<32).map(UInt8.init))

        manager.removeObject(forKey: key)
        #expect(manager.set(value, forKey: key))
        #expect(manager.data(forKey: key) == value)

        manager.removeObject(forKey: key)
        #expect(manager.data(forKey: key) == nil)
    }

    @Test func testStringRoundTripsWithoutBooleanCoercion() async {
        let manager = KeychainManager.shared
        let key = testKey + "_string"
        let value = "provider-bound-handoff"

        manager.removeObject(forKey: key)
        #expect(manager.set(value, forKey: key))
        #expect(manager.string(forKey: key) == value)
        #expect(manager.bool(forKey: key) == false)

        manager.removeObject(forKey: key)
    }
}
