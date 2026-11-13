import Foundation

/// Centralizes process-level test detection for production side-effect gates
/// and Debug-only UI-test fixtures.
enum TestExecutionCoordinator {
    /// Narrow runtime proof for fixture gates that must not accept an
    /// environment marker alone.
    static var isXCTestRuntimeLoaded: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    static var isRunningUITests: Bool {
        isRunningUITests(environment: ProcessInfo.processInfo.environment)
    }

    static var isRunningTests: Bool {
        isRunningTests(
            environment: ProcessInfo.processInfo.environment,
            isXCTestRuntimeLoaded: isXCTestRuntimeLoaded
        )
    }

    static var isRunningUnitTests: Bool {
        isRunningUnitTests(environment: ProcessInfo.processInfo.environment,
                           isXCTestRuntimeLoaded: isXCTestRuntimeLoaded)
    }

    static func isRunningUnitTests(environment: [String: String], isXCTestRuntimeLoaded: Bool) -> Bool {
        !isRunningUITests(environment: environment) &&
            isRunningTests(environment: environment, isXCTestRuntimeLoaded: isXCTestRuntimeLoaded)
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
