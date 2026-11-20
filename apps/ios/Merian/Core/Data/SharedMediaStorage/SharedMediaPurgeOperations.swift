import Foundation

/// Cleanup only: the existing coordinator supplies actual drain evidence and
/// fenced transactions. This helper never starts a writer or invokes a provider.
@MainActor
struct SharedMediaPurgeOperations {
    let storage: SharedMediaStorageRepository
    let sourceIO: SharedMediaInboxIO
    let destinationIO: SharedMediaInboxDestinationIO
    let access: SharedMediaPurgeAccess
    let closeSource: (SharedMediaInboxSource) -> SharedMediaInboxWriterClosure

    func run() async throws -> SharedMediaPurgeCompletion {
        if try storage.isPurgeComplete(access) { return try storage.finishPurge(access) }
        // Finish committed source-retirement intents before touching holds.
        for source in try read({ try $0.sources() }).filter({ $0.phase == "retiring" }) {
            try await releaseSource(source)
        }
        for handoff in try read({ try $0.handoffs.all() }).filter(\.detached) {
            try await discardDetached(handoff)
        }
        let held = Set(try read { try $0.handoffs.all() }.map { $0.request.source.id })
        for source in try read({ try $0.sources() }).filter({ !held.contains($0.handle.id) }) {
            try await discardSource(source)
        }
        let attached = try read { try $0.handoffs.all() }
        let sources = try read { try $0.sources() }
        guard attached.count <= 1, attached.allSatisfy({ !$0.detached }), sources.count <= 1 else {
            throw SharedMediaStorageFailure.conflict
        }
        if let initial = attached.first {
            guard sources.first?.handle.id == initial.request.source.id else { throw SharedMediaStorageFailure.conflict }
            // Now A=0 and S<=32 MiB: incomplete abandonment fits S+H+A<=96 MiB.
            let closure = try await destinationIO.closure(initial)
            let closed = try write { try $0.handoffs.close(closure) }
            let proof = try await destinationIO.closure(closed)
            try write { try $0.handoffs.abandon(proof) }
            if let detached = try read({ try $0.handoffs.all() }).first {
                guard detached.detached else { throw SharedMediaStorageFailure.conflict }
                try await discardDetached(detached)
            }
        }
        for source in try read({ try $0.sources() }) { try await discardSource(source) }

        // Old retiring pairs precede planned replacements. Exact persisted
        // intents allow absence reconciliation after an interrupted unlink.
        let pairs = try read { try $0.derivatives.all() }.sorted {
            if ($0.phase == "retiring") != ($1.phase == "retiring") { return $0.phase == "retiring" }
            return $0.request.id.uuidString < $1.request.id.uuidString
        }
        for pair in pairs { try await discardPair(pair.request) }
        for handle in try read({ try $0.photos.purgeHandles() }) { try await discardOriginal(handle) }
        try await destinationIO.prune(read { try $0.photos.inventory() })
        do { return try storage.finishPurge(access) } catch { return try storage.finishPurge(access) } // Fresh terminal readback; no file or AI retry.
    }

    private func discardSource(_ initial: SharedMediaInboxSource) async throws {
        let source = try write { try $0.closeWriter(closeSource(initial)) }
        let inspection = try await sourceIO.inspectRetirement(source)
        guard source.inode == nil || inspection.partial != "absent" || inspection.final != "absent" else { throw SharedMediaStorageFailure.conflict }
        let retiring = try write { try $0.retire(inspection) }
        try await releaseSource(retiring)
    }
    private func releaseSource(_ source: SharedMediaInboxSource) async throws {
        try Task.checkCancellation()
        let intent = try storage.inboxRetirement(source.handle, purge: access)
        let proof = try await sourceIO.release(intent)
        try write(releasing: true) { try $0.release(proof) }
    }
    private func discardDetached(_ initial: SharedMediaInboxHandoff) async throws {
        if initial.phase != "detachedRetiring" {
            let inspection = try await destinationIO.inspectRetirement(initial)
            guard initial.inode == nil || inspection.identity.partial != "absent" || inspection.identity.final != "absent" else { throw SharedMediaStorageFailure.conflict }
            _ = try write { try $0.handoffs.retireDetached(inspection) }
        }
        try Task.checkCancellation()
        let intent = try storage.detachedRetirement(initial.request, purge: access)
        let proof = try await destinationIO.release(intent)
        try write(releasing: true) { try $0.handoffs.releaseDetached(proof) }
    }
    private func discardPair(_ request: SharedMediaDerivativeRequest) async throws {
        guard var pair = try read({ try $0.derivatives.saved(request) }) else { return }
        if pair.phase != "retiring" {
            for work in pair.work {
                let closure = try await destinationIO.closure(work)
                pair = try write { try $0.derivatives.close(closure) }
            }
            var inspections: [SharedMediaDerivativeInspection] = []
            for work in pair.work {
                let inspection = try await destinationIO.inspectRetirement(work)
                guard work.inode == nil || inspection.identity.partial != "absent" || inspection.identity.final != "absent" else { throw SharedMediaStorageFailure.conflict }
                inspections.append(inspection)
            }
            _ = try write { try $0.derivatives.retire(request, inspections: inspections) }
        }
        var proofs: [SharedMediaDerivativeRelease] = []
        for intent in try storage.derivativeRetirements(request, purge: access) {
            try Task.checkCancellation()
            proofs.append(try await destinationIO.release(intent))
        }
        try write(releasing: true) { try $0.derivatives.release(request, proofs: proofs) }
    }
    private func discardOriginal(_ handle: PhotoOriginalReference) async throws {
        if case .live(let file) = try storage.purgePhotoState(handle, access: access) {
            let inspection = try await destinationIO.inspectOriginal(file)
            try storage.purgeRetirePhoto(handle, inspection: inspection, access: access)
        }
        switch try storage.purgePhotoState(handle, access: access) {
        case .absent: return // Another surviving reference still owns these bytes.
        case .live: throw SharedMediaStorageFailure.conflict
        case .retiring(let intent):
            try Task.checkCancellation()
            let proof = try await destinationIO.releaseOriginal(intent)
            try storage.purgeReleasePhoto(proof, access: access)
        }
    }
    private func read<T>(_ body: (SharedMediaInboxLedger) throws -> T) throws -> T {
        try Task.checkCancellation()
        return try storage.purgeRead(access, body)
    }
    private func write<T>(releasing: Bool = false, _ body: (SharedMediaInboxLedger) throws -> T) throws -> T {
        try Task.checkCancellation()
        return try storage.purgeWrite(access, before: releasing ? .beforeReleaseSave : .beforeRetirementSave,
            after: releasing ? .afterReleaseSave : .afterRetirementSave, body)
    }
}
