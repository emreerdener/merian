import Foundation
import Testing

/// Process-wide mutable resources that require exclusive ownership in tests.
enum SharedProcessStateResource: Hashable, Sendable {
    case networkClientOverrides
}

/// Serializes only tests that mutate the same process-wide resource.
///
/// Swift Testing's built-in `.serialized` trait orders tests within one suite,
/// but separate suites may still run concurrently. Apply this trait to every
/// suite or test that temporarily owns one of the resources above.
struct SharedProcessStateTestTrait: SuiteTrait, TestTrait, TestScoping {
    let resource: SharedProcessStateResource

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

        await SharedProcessStateGate.shared.acquire(resource)
        do {
            try await function()
            await SharedProcessStateGate.shared.release(resource)
        } catch {
            await SharedProcessStateGate.shared.release(resource)
            throw error
        }
    }
}

extension Trait where Self == SharedProcessStateTestTrait {
    static func sharedProcessState(
        _ resource: SharedProcessStateResource
    ) -> Self {
        SharedProcessStateTestTrait(resource: resource)
    }
}

private actor SharedProcessStateGate {
    static let shared = SharedProcessStateGate()

    private var heldResources: Set<SharedProcessStateResource> = []
    private var waiters: [
        SharedProcessStateResource: [CheckedContinuation<Void, Never>]
    ] = [:]

    func acquire(_ resource: SharedProcessStateResource) async {
        guard heldResources.contains(resource) else {
            heldResources.insert(resource)
            return
        }

        await withCheckedContinuation { continuation in
            waiters[resource, default: []].append(continuation)
        }
    }

    func release(_ resource: SharedProcessStateResource) {
        guard var resourceWaiters = waiters[resource],
              !resourceWaiters.isEmpty else {
            heldResources.remove(resource)
            waiters[resource] = nil
            return
        }

        let next = resourceWaiters.removeFirst()
        waiters[resource] = resourceWaiters.isEmpty ? nil : resourceWaiters
        next.resume()
    }
}
