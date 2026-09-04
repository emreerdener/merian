import Foundation
import Testing

/// Process-wide mutable resources that require exclusive ownership in tests.
enum SharedProcessStateResource: Hashable, Sendable {
    case appIconBadgeCoordinator
    case gamificationManager
    case networkClientOverrides
    case offlineQueueManager
}

/// Serializes only tests that mutate the same process-wide resource.
///
/// Swift Testing's built-in `.serialized` trait orders tests within one suite,
/// but separate suites may still run concurrently. Apply this trait to every
/// suite or test that temporarily owns one of the resources above.
struct SharedProcessStateTestTrait: SuiteTrait, TestTrait, TestScoping {
    let resources: Set<SharedProcessStateResource>

    var isRecursive: Bool { true }

    func provideScope(
        for _: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // Suites have no executable case of their own. Their recursive trait
        // application scopes each descendant test without double-locking.
        guard testCase != nil else {
            try await function()
            return
        }

        try await SharedProcessStateGate.shared.withResources(resources) {
            if resources.contains(.offlineQueueManager) {
                try await OfflineQueueTestState.withState(performing: function)
            } else {
                try await function()
            }
        }
    }
}

extension Trait where Self == SharedProcessStateTestTrait {
    static func sharedProcessState(
        _ resources: SharedProcessStateResource...
    ) -> Self {
        SharedProcessStateTestTrait(resources: Set(resources))
    }
}
