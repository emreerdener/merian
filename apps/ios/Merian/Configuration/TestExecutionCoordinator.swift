import Foundation

/// Centralizes process-level test detection for production side-effect gates
/// and Debug-only UI-test fixtures.
enum TestExecutionCoordinator {
    static var isRunningUITests: Bool {
        isRunningUITests(environment: ProcessInfo.processInfo.environment)
    }

    static var isRunningTests: Bool {
        isRunningTests(
            environment: ProcessInfo.processInfo.environment,
            isXCTestRuntimeLoaded: NSClassFromString("XCTestCase") != nil
        )
    }

    static func isRunningUITests(environment: [String: String]) -> Bool {
        environment["UITesting"] == "true"
    }

    static func isRunningTests(
        environment: [String: String],
        isXCTestRuntimeLoaded: Bool
    ) -> Bool {
        isRunningUITests(environment: environment) ||
            environment["XCTestConfigurationFilePath"] != nil ||
            isXCTestRuntimeLoaded
    }
}
