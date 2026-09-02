import XCTest

/// Holds the same lease as Swift Testing through XCTest's entire per-test
/// lifecycle, including synchronous setup and teardown in feature subclasses.
@MainActor
class OfflineQueueTestCase: XCTestCase {
    private var sharedStateLease: SharedProcessStateGate.Lease?
    private var queueState: OfflineQueueTestState?

    override func setUp() async throws {
        try await super.setUp()
        let lease = try await SharedProcessStateGate.shared.acquire([
            .networkClientOverrides, .offlineQueueManager
        ])
        do {
            try Task.checkCancellation()
            sharedStateLease = lease
            queueState = OfflineQueueTestState()
        } catch {
            await SharedProcessStateGate.shared.release(lease)
            throw error
        }
    }

    override func tearDown() async throws {
        if let lease = sharedStateLease {
            queueState?.restore()
            queueState = nil
            await SharedProcessStateGate.shared.release(lease)
            sharedStateLease = nil
        }
        try await super.tearDown()
    }
}
