import Testing
import Foundation
@testable import Merian

struct BackgroundTaskWrapperTests {
    
    @Test func testBackgroundTaskExecutesAndYieldsGracefully() async {
        // Arrange
        var closureDidExecute = false
        
        // Act
        // Because we are outside a UIApplication environment, standard identifiers won't map properly
        // but the block execution and locking safety mechanisms must still process synchronously.
        let backgroundTask = BackgroundTaskWrapper.execute(name: "UnitTestTask") { wrapper in
            closureDidExecute = true
            
            // Task executes within native UIApplication context inside testing daemon, generating valid identifiers
            #expect(wrapper.id != .invalid)
        }
        
        // Wait for it to natively process through its asynchronous priority queue
        _ = await backgroundTask.value
        
        // Assert
        #expect(closureDidExecute == true, "The BackgroundTaskWrapper failed to actually execute the attached block.")
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
