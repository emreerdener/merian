import Foundation
import SwiftData

/// Accepted whole-library cleanup, distinct from normal media admission and
/// per-original abandonment. All mutations follow the complete durable
/// manifest. Failure retains the operation and its exact recovery evidence.
@MainActor
enum SharedMediaNativeLibraryErasure {
    @MainActor struct Completion {
        private let containerID: ObjectIdentifier
        private let check: () throws -> Void
        fileprivate init(container: ModelContainer, check: @escaping () throws -> Void) {
            containerID = ObjectIdentifier(container); self.check = check
        }
        func validate(in container: ModelContainer) throws {
            guard ObjectIdentifier(container) == containerID else { throw SharedMediaStorageFailure.stale }
            try check()
            try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: check)
            try check()
        }
    }

    static func erase(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                      authorization: SharedMediaNativeErasureAuthorization,
                      runtimeCheckpoint: @escaping () throws -> Void) async throws -> Completion {
        let operation = try authorization.require(container: container)
        if let empty = try SharedMediaNativeErasureEmptyProbe.openIfAbsent(container: container, admission: admission,
            authorization: authorization, runtimeCheckpoint: runtimeCheckpoint) {
            let completion = Completion(container: container) { try empty.requirePhysicalScope() }
            try completion.validate(in: container); return completion
        }
        let parent = try SharedMediaNativeErasureParent.open(container: container, admission: admission,
            authorization: authorization, runtimeCheckpoint: runtimeCheckpoint)
        return try await erase(container: container, parent: parent, operationID: operation.operationID)
    }

    static func erase(container: ModelContainer, parent: SharedMediaNativeErasureParent, operationID: UUID,
                      journalBoundary: (SharedMediaNativeErasureJournal.Boundary) throws -> Void = { _ in },
                      treeBoundary: (SharedMediaNativeErasureTree.Boundary) throws -> Void = { _ in }) async throws -> Completion {
        try parent.requireOperation(operationID)
        let context = ModelContext(container); context.autosaveEnabled = false
        var query = FetchDescriptor<SharedMediaInventoryRecord>(); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let inventory = rows.first else {
            try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: { try parent.check() })
            let identity = try parent.emptyLibraryIdentity()
            let completion = Completion(container: container) {
                try parent.requireOperation(operationID)
                guard try parent.emptyPhysicalIdentity() == identity else { throw SharedMediaStorageFailure.stale }
            }
            try completion.validate(in: container); return completion
        }
        let profile = try SharedMediaNativeAppEligibility.profileAssertion(inventory)
        var saved: SharedMediaNativeErasureJournal.Snapshot
        if inventory.phaseRaw == SharedMediaNativeAppProfile.phase {
            let candidate = try await SharedMediaNativeErasureManifestBuilder.build(container: container,
                parent: parent, operationID: operationID)
            guard candidate.profile == profile else { throw SharedMediaStorageFailure.stale }
            saved = try SharedMediaNativeErasureJournal.begin(candidate.header, container: container, profile: profile,
                checkpoint: { try parent.check() }, boundary: journalBoundary)
            saved = try await append(candidate, container: container, parent: parent, boundary: journalBoundary)
        } else {
            saved = try SharedMediaNativeErasureJournal.read(container: container, profile: profile,
                operationID: operationID, checkpoint: { try parent.check() })
            try parent.require(header: saved.header, profile: profile)
            if saved.state.stage == .preparing {
                let candidate = try await SharedMediaNativeErasureManifestBuilder.build(container: container,
                    parent: parent, operationID: operationID, resuming: saved.header)
                saved = try await append(candidate, container: container, parent: parent, boundary: journalBoundary)
            }
        }
        let header = saved.header
        try parent.require(header: header, profile: profile)
        if saved.state.stage == .preparing {
            saved = try SharedMediaNativeErasureJournal.retire(container: container, profile: profile,
                operationID: operationID, checkpoint: { try parent.check() }, boundary: journalBoundary)
        }
        // The builder's source owners have exited. Only the parent/store fence
        // survives, so descriptor replay can acquire each child exclusively.
        let tree = try parent.makeTree(profile: profile, header: header) { removing, body in
            try SharedMediaNativeErasureJournal.visitManifest(container: container, profile: profile, header: header,
                removing: removing, checkpoint: { try parent.require(header: header, profile: profile) }, body: body)
        }
        let absence = try saved.state.stage == .retiring ? tree.retire(boundary: treeBoundary) : tree.absence()
        if saved.state.stage == .retiring {
            saved = try SharedMediaNativeErasureJournal.complete(container: container, profile: profile,
                operationID: operationID, checkpoint: { try parent.check() }, absence: absence, boundary: journalBoundary)
        }
        if saved.state.stage == .complete {
            saved = try SharedMediaNativeErasureJournal.clearSourceRows(container: container, profile: profile,
                operationID: operationID, checkpoint: { try parent.check() }, absence: absence, boundary: journalBoundary)
        }
        guard saved.state.stage == .cleared else { throw SharedMediaStorageFailure.conflict }
        let terminal = try tree.persistTerminal(container: container)
        try SharedMediaNativeErasureJournal.retireCarrier(container: container, profile: profile, header: header,
            terminal: terminal, checkpoint: { try parent.check() }, boundary: journalBoundary)
        return try completion(container: container, parent: parent, terminal: terminal)
    }

    #if DEBUG
    /// Exercises the same owner against isolated qualification directories.
    /// Production openers remain unavailable during test execution.
    static func qualification(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                              authorization: SharedMediaNativeErasureAuthorization, support: URL,
                              runtimeCheckpoint: @escaping () throws -> Void) async throws -> Completion {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        let operation = try authorization.require(container: container)
        if let empty = try SharedMediaNativeErasureEmptyProbe.qualification(container: container, admission: admission,
            authorization: authorization, support: support, runtimeCheckpoint: runtimeCheckpoint) {
            let completion = Completion(container: container) { try empty.requirePhysicalScope() }
            try completion.validate(in: container); return completion
        }
        let parent = try SharedMediaNativeErasureParent.qualification(container: container, admission: admission,
            authorization: authorization, parent: support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName),
            runtimeCheckpoint: runtimeCheckpoint)
        return try await erase(container: container, parent: parent, operationID: operation.operationID)
    }
    #endif

    private static func append(_ candidate: SharedMediaNativeErasureManifestBuilder.Candidate,
                               container: ModelContainer, parent: SharedMediaNativeErasureParent,
                               boundary: (SharedMediaNativeErasureJournal.Boundary) throws -> Void) async throws
        -> SharedMediaNativeErasureJournal.Snapshot {
        _ = try await candidate.spool.visitPages(profile: candidate.profile, operationID: candidate.header.operationID) { bytes in
            _ = try SharedMediaNativeErasureJournal.append(bytes, container: container, profile: candidate.profile,
                operationID: candidate.header.operationID, checkpoint: { try parent.check() }, boundary: boundary)
        }
        let saved = try SharedMediaNativeErasureJournal.read(container: container, profile: candidate.profile,
            operationID: candidate.header.operationID, checkpoint: { try parent.check() })
        guard saved.header == candidate.header, saved.hasCompleteManifest else { throw SharedMediaStorageFailure.stale }
        return saved
    }

    private static func completion(container: ModelContainer, parent: SharedMediaNativeErasureParent,
                                   terminal: SharedMediaNativeErasureTerminal) throws -> Completion {
        let value = Completion(container: container) { try parent.check(); try terminal.requireCurrent() }
        try value.validate(in: container)
        return value
    }
}
