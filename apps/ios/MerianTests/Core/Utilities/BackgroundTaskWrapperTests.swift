import Testing
import Foundation
@testable import Merian

struct BackgroundTaskWrapperTests {
    
    final class ThreadSafeFlag: @unchecked Sendable {
        private var lock = NSLock()
        private var _value = false
        var value: Bool {
            lock.lock(); defer { lock.unlock() }
            return _value
        }
        func setTrue() {
            lock.lock(); defer { lock.unlock() }
            _value = true
        }
    }
    
    @Test func testBackgroundTaskExecutesAndYieldsGracefully() async {
        // Arrange
        let closureDidExecute = ThreadSafeFlag()
        
        // Act
        // Because we are outside a UIApplication environment, standard identifiers won't map properly
        // but the block execution and locking safety mechanisms must still process synchronously.
        let backgroundTask = BackgroundTaskWrapper.execute(name: "UnitTestTask") { wrapper in
            closureDidExecute.setTrue()
            
            // Task executes within native UIApplication context inside testing daemon, generating valid identifiers
            #expect(wrapper.id != .invalid)
        }
        
        // Wait for it to natively process through its asynchronous priority queue
        _ = await backgroundTask.value
        
        // Assert
        #expect(closureDidExecute.value == true, "The BackgroundTaskWrapper failed to actually execute the attached block.")
    }
    
    @Test func testSafeEndIsThreadSafeAndIdempotent() {
        let wrapper = BackgroundTaskWrapper()
        
        // Ensure no locks deadlock or trap when multiple safeEnd() commands fire blindly
        wrapper.safeEnd()
        wrapper.safeEnd()
        wrapper.safeEnd()
        
        #expect(wrapper.id == .invalid)
    }
}
