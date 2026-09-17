@testable import Merian
import Testing

@Suite("Test execution coordinator")
struct TestExecutionCoordinatorTests {
    @Test func uiTestDetectionRequiresTheExplicitTrueValue() {
        #expect(TestExecutionCoordinator.isRunningUITests(environment: [
            "UITesting": "true"
        ]))
        #expect(!TestExecutionCoordinator.isRunningUITests(environment: [
            "UITesting": "false"
        ]))
        #expect(!TestExecutionCoordinator.isRunningUITests(environment: [:]))
    }

    @Test func testDetectionAcceptsEachEstablishedProcessSignal() {
        #expect(TestExecutionCoordinator.isRunningTests(
            environment: ["UITesting": "true"],
            isXCTestRuntimeLoaded: false
        ))
        #expect(TestExecutionCoordinator.isRunningTests(
            environment: ["XCTestConfigurationFilePath": ""],
            isXCTestRuntimeLoaded: false
        ))
        #expect(TestExecutionCoordinator.isRunningTests(
            environment: [:],
            isXCTestRuntimeLoaded: true
        ))
        #expect(!TestExecutionCoordinator.isRunningTests(
            environment: [:],
            isXCTestRuntimeLoaded: false
        ))
    }

    @Test func coordinatorAndRawProcessSignalsHaveOneConfigurationOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )
        let owners = sources.compactMap { source in
            source.contents.contains("enum TestExecutionCoordinator {")
                ? source.relativePath
                : nil
        }

        #expect(owners == ["Configuration/TestExecutionCoordinator.swift"])

        for signal in [
            "XCTestConfigurationFilePath",
            "NSClassFromString(\"XCTestCase\")",
            "environment[\"UITesting\"]"
        ] {
            let signalOwners = sources.compactMap { source in
                source.contents.contains(signal) ? source.relativePath : nil
            }
            #expect(
                signalOwners == ["Configuration/TestExecutionCoordinator.swift"],
                "Raw test signal \(signal) changed ownership"
            )
        }
    }
}
