import Foundation
import SwiftData

/// Invocation-local read facts for rebuilding an interrupted erasure manifest.
/// Never usable as normal admission, byte access, mutation or unlink authority.
/// The cleanup owner independently retains its accepted account scope and all
/// physical locks. Full journal/graph reads bracket the body; per-row checks
/// validate the exact header without turning the audit into quadratic work.
@MainActor
final class SharedMediaNativeErasureAuditScope {
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeAppEligibility.Header
    private let identity: SharedMediaNativeScopeIdentity
    private let snapshot: SharedMediaNativeErasureJournal.Snapshot
    private let containerID: ObjectIdentifier
    private let checkpoint: () throws -> Void
    private var active = true

    private init(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                 snapshot: SharedMediaNativeErasureJournal.Snapshot,
                 checkpoint: @escaping () throws -> Void) throws {
        self.profile = profile; self.snapshot = snapshot; self.checkpoint = checkpoint
        containerID = ObjectIdentifier(container)
        identity = .init(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let context = ModelContext(container); context.autosaveEnabled = false
        header = try SharedMediaNativeAppEligibility.erasureSnapshot(context: context, scope: identity, expected: snapshot.state)
    }

    static func withVerified<T>(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                                checkpoint: @escaping () throws -> Void,
                                body: (SharedMediaNativeErasureAuditScope) async throws -> T) async throws -> T {
        let before = try SharedMediaNativeErasureJournal.read(container: container, profile: profile,
            operationID: operationID, checkpoint: checkpoint)
        guard before.state.stage == .preparing else { throw SharedMediaStorageFailure.closed }
        let scope = try Self(container: container, profile: profile, snapshot: before, checkpoint: checkpoint)
        defer { scope.active = false }
        try scope.requireCurrent(ModelContext(container))
        let result = try await body(scope)
        try scope.requireCurrent(ModelContext(container))
        guard try SharedMediaNativeErasureJournal.read(container: container, profile: profile,
            operationID: operationID, checkpoint: checkpoint) == before else { throw SharedMediaStorageFailure.stale }
        return result
    }

    func requireCurrent(_ context: ModelContext) throws {
        try Task.checkCancellation(); try checkpoint()
        guard active, ObjectIdentifier(context.container) == containerID,
              !context.hasChanges, !context.container.mainContext.hasChanges,
              try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1,
              try context.fetchCount(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()) == 1,
              try SharedMediaNativeAppEligibility.erasureSnapshot(context: context, scope: identity,
                expected: snapshot.state) == header else { throw SharedMediaStorageFailure.stale }
    }
}
