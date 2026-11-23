import Foundation
import SwiftData

/// Invocation-local accounting facts backed by a live, locked capture root.
/// This scope grants no byte reads, file creation, adoption, or retirement.
@MainActor
final class SharedMediaCaptureArtifactInspection {
    let profile: SharedMediaNativeAppProfile
    let inventory: SharedMediaCaptureArtifactFiles.Inventory
    private let files: SharedMediaCaptureArtifactFiles
    private let containerID: ObjectIdentifier
    private let checkpoint: () throws -> Void
    private var active = true
    private let cleanupTarget: UUID?
    private let initialErasure: Bool

    private init(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                 files: SharedMediaCaptureArtifactFiles, inventory: SharedMediaCaptureArtifactFiles.Inventory, cleanupTarget: UUID?,
                 initialErasure: Bool, checkpoint: @escaping () throws -> Void) {
        containerID = ObjectIdentifier(container); self.profile = profile
        self.files = files; self.inventory = inventory; self.checkpoint = checkpoint; self.cleanupTarget = cleanupTarget
        self.initialErasure = initialErasure
    }

    static func withVerified<T>(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                files: SharedMediaCaptureArtifactFiles, cleanupTarget: UUID? = nil, checkpoint: @escaping () throws -> Void,
                                body: (SharedMediaCaptureArtifactInspection) async throws -> T) async throws -> T {
        try await withScope(container: container, profile: profile, files: files, cleanupTarget: cleanupTarget,
            initialErasure: false, checkpoint: checkpoint, body: body)
    }

    /// Only the aggregate erasure audit may describe a ledger-bound empty
    /// partial without a saved writer receipt. The inspection cannot escape
    /// this fixed-result factory or grant normal admission or file mutation.
    static func auditInitialErasure(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                    files: SharedMediaCaptureArtifactFiles,
                                    header: @escaping () throws -> SharedMediaNativeAppEligibility.Header,
                                    betweenPages: @escaping () async throws -> Void) async throws -> SharedMediaNativeScopedSnapshot {
        let expected = try header()
        return try await withScope(container: container, profile: profile, files: files, cleanupTarget: nil,
            initialErasure: true, checkpoint: { guard try header() == expected else { throw SharedMediaStorageFailure.stale } }) { capture in
                try await SharedMediaOrdinaryInspection.auditInitialErasure(container: container, profile: profile,
                    capture: capture, header: header, betweenPages: betweenPages)
            }
    }

    private static func withScope<T>(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                     files: SharedMediaCaptureArtifactFiles, cleanupTarget: UUID?, initialErasure: Bool,
                                     checkpoint: @escaping () throws -> Void,
                                     body: (SharedMediaCaptureArtifactInspection) async throws -> T) async throws -> T {
        let context = ModelContext(container); context.autosaveEnabled = false
        let inventory = try await files.verify(context: context, profile: profile, checkpoint: checkpoint)
        if inventory.ambiguousEmptyPartials != 0, !initialErasure {
            guard inventory.ambiguousEmptyPartials == 1, let cleanupTarget else { throw SharedMediaStorageFailure.closed }
            let target = try SharedMediaCaptureArtifactLedger.read(id: cleanupTarget, profile: profile,
                rootBindingSHA256: files.rootBindingSHA256, context: context)
            if target.request.format == .v1 {
                guard !target.request.role.rawValue.hasPrefix("source_") else { throw SharedMediaStorageFailure.closed }
                try SharedMediaCapturePreparedAttempt.requireMember(target.request, context: context,
                    phases: [.preparing, .abortingPreparation])
            }
            guard try files.inspect(target).ambiguous else { throw SharedMediaStorageFailure.closed }
        }
        let scope = Self(container: container, profile: profile, files: files, inventory: inventory,
            cleanupTarget: cleanupTarget, initialErasure: initialErasure, checkpoint: checkpoint)
        defer { scope.active = false }
        try scope.requireCurrent(context)
        let result = try await body(scope)
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        try scope.requireCurrent(fresh)
        guard try await files.verify(context: fresh, profile: profile, checkpoint: checkpoint) == inventory else {
            throw SharedMediaStorageFailure.stale
        }
        try scope.requireCurrent(fresh)
        return result
    }

    /// The owner retains its store/account fence. Header checks keep page work
    /// linear; full ledger and physical audits bracket the entire invocation.
    func requireCurrent(_ context: ModelContext) throws {
        try Task.checkCancellation()
        guard active, ObjectIdentifier(context.container) == containerID,
              !context.hasChanges, !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.closed }
        try checkpoint(); try files.check()
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        guard try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope) == inventory.ledger.header else {
            throw SharedMediaStorageFailure.stale
        }
    }

    func allocation(_ id: UUID, context: ModelContext) throws {
        try requireCurrent(context)
        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.allocationID == id })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        let value = try SharedMediaCaptureArtifactLedger.auditRead(id: row.id, profile: profile,
            rootBindingSHA256: files.rootBindingSHA256, context: context)
        guard try !files.inspect(value).ambiguous || value.request.id == cleanupTarget || initialErasure else { throw SharedMediaStorageFailure.closed }
        try requireCurrent(context)
    }

    func includeLiability(context: ModelContext, totals: inout SharedMediaStoragePolicy.Totals) throws {
        try requireCurrent(context)
        let value = inventory.ledger
        // Partial bytes remain covered by their full reservation. Charging them
        // again would double count an interrupted writer's physical liability.
        try totals.includePhotoPhysical(
            materialized: SharedMediaStoragePolicy.add(value.materializedBytes, value.metadataBytes),
            reserved: SharedMediaStoragePolicy.add(value.reservedBytes, value.futureMetadataReservationBytes))
        try requireCurrent(context)
    }
}
