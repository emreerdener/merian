@testable import Merian
import SwiftData
import XCTest

final class ModelContainerBootstrapperTests: XCTestCase {
    func testFallbackInMemoryBootstrapCreatesLivePlanFreeContainer() {
        let outcome = ModelContainerBootstrapper.fallbackInMemoryBootstrap(
            reason: "Unit safe mode"
        )

        XCTAssertNotNil(outcome.container)
        XCTAssertEqual(outcome.startupStoreState, .safeMode)
        XCTAssertEqual(outcome.startupNotice?.title, "Safe Mode Enabled")
        XCTAssertEqual(outcome.telemetryEvent?.outcome, "safe_mode")
    }

    func testFallbackInMemoryBootstrapMarksSafeMode() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: LocalScanRecord.self,
            ScanCollection.self,
            OfflineQueuedScan.self,
            configurations: configuration
        )

        let outcome = ModelContainerBootstrapper.fallbackInMemoryBootstrap(
            reason: "Unit safe mode",
            makeInMemoryContainer: { container }
        )

        XCTAssertNotNil(outcome.container)
        XCTAssertEqual(outcome.startupStoreState, .safeMode)
        XCTAssertEqual(outcome.startupNotice?.title, "Safe Mode Enabled")
        XCTAssertEqual(outcome.startupNotice?.message, "Unit safe mode")
        XCTAssertEqual(outcome.telemetryEvent?.outcome, "safe_mode")
        XCTAssertEqual(
            outcome.telemetryEvent?.reason,
            "persistent_store_unavailable"
        )
    }

    func testFallbackInMemoryBootstrapReportsBlockedWhenMemoryStoreFails() {
        let outcome = ModelContainerBootstrapper.fallbackInMemoryBootstrap(
            reason: "Unit safe mode",
            makeInMemoryContainer: { throw StubError.containerUnavailable }
        )

        XCTAssertNil(outcome.container)
        XCTAssertEqual(outcome.startupStoreState, .safeMode)
        XCTAssertEqual(outcome.startupNotice?.title, "Startup Blocked")
        XCTAssertEqual(
            outcome.telemetryEvent?.outcome,
            "blocked"
        )
        XCTAssertEqual(
            outcome.telemetryEvent?.reason,
            "persistent_and_memory_store_unavailable"
        )
    }

    private enum StubError: Error {
        case containerUnavailable
    }
}
