import Foundation
import SwiftData

/// Read-only accounting evidence. The private variants preserve their original
/// admission rules; neither exposes a normal operation or filesystem capability.
@MainActor
final class SharedMediaCaptureAuditEvidence {
    let profile: SharedMediaNativeAppProfile
    let inventory: SharedMediaCaptureArtifactFiles.Inventory
    private let validate: (ModelContext) throws -> Void

    private init(profile: SharedMediaNativeAppProfile, inventory: SharedMediaCaptureArtifactFiles.Inventory,
                 validate: @escaping (ModelContext) throws -> Void) {
        self.profile = profile; self.inventory = inventory; self.validate = validate
    }

    static func ready(_ inspection: SharedMediaCaptureArtifactInspection) -> Self {
        Self(profile: inspection.profile, inventory: inspection.inventory, validate: inspection.requireCurrent)
    }

    static func withErasure<T>(container: ModelContainer, scope: SharedMediaNativeErasureAuditScope,
                               files: SharedMediaCaptureArtifactFiles, checkpoint: @escaping () throws -> Void,
                               body: (SharedMediaCaptureAuditEvidence) async throws -> T) async throws -> T {
        let context = ModelContext(container); context.autosaveEnabled = false
        try scope.requireCurrent(context)
        let inventory = try await files.verifyForErasure(context: context, erasure: scope, checkpoint: checkpoint)
        // An unrecorded partial cannot supply ownership for an erasure manifest.
        guard inventory.ambiguousEmptyPartials == 0 else { throw SharedMediaStorageFailure.closed }
        var active = true
        let evidence = Self(profile: scope.profile, inventory: inventory) { context in
            guard active else { throw SharedMediaStorageFailure.closed }
            try checkpoint(); try scope.requireCurrent(context); try files.check()
        }
        defer { active = false }
        let result = try await body(evidence)
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        try evidence.requireCurrent(fresh)
        guard try await files.verifyForErasure(context: fresh, erasure: scope, checkpoint: checkpoint) == inventory else {
            throw SharedMediaStorageFailure.stale
        }
        try evidence.requireCurrent(fresh)
        return result
    }

    func requireCurrent(_ context: ModelContext) throws { try validate(context) }
}
