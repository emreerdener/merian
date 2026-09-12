import Foundation
@testable import Merian
import Testing

struct BackgroundTaskWrapperTests {
    final class ThreadSafeFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var storedValue = false

        var value: Bool {
            lock.withLock { storedValue }
        }

        func setTrue() {
            lock.withLock { storedValue = true }
        }
    }

    @Test func backgroundTaskExecutesAndYieldsGracefully() async {
        let closureDidExecute = ThreadSafeFlag()

        // The testing daemon supplies the UIApplication context needed for a
        // real background-task identifier.
        let backgroundTask = BackgroundTaskWrapper.execute(
            name: "UnitTestTask"
        ) { wrapper in
            closureDidExecute.setTrue()
            #expect(wrapper.id != .invalid)
        }

        _ = await backgroundTask.value

        #expect(closureDidExecute.value)
    }

    @Test func safeEndIsThreadSafeAndIdempotent() {
        let wrapper = BackgroundTaskWrapper()

        wrapper.safeEnd()
        wrapper.safeEnd()
        wrapper.safeEnd()

        #expect(wrapper.id == .invalid)
    }
}
