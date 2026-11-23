import Foundation
import SwiftData

enum SharedMediaCaptureDraftJournalBoundary: CaseIterable { case beforeSave, afterSave, beforeReadback }

/// Metadata operations use the same registered root/account audit as original
/// materialization. A lost acknowledgement retries the exact successor, never
/// rebases an old composition over newer edits.
@MainActor
enum SharedMediaCaptureDraftJournalStore {
    typealias Journal = SharedMediaCaptureDraftJournal
    typealias Receipt = SharedMediaCaptureDraftJournalReceipt

    static func saveEditing(_ next: Journal, replacing expected: Receipt.Snapshot?, container: ModelContainer,
                            authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                            availableBytes: () throws -> Int64,
                            boundary: (SharedMediaCaptureDraftJournalBoundary) throws -> Void = { _ in }) async throws -> Receipt.Snapshot {
        try await persist(next, replacing: expected, container: container, authority: authority, files: files,
            availableBytes: availableBytes, boundary: boundary, discharge: false)
    }

    static func beginPreparationAbort(_ expected: Receipt.Snapshot, container: ModelContainer,
                                      authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                                      availableBytes: () throws -> Int64, cleanupTarget: UUID?,
                                      boundary: (SharedMediaCaptureDraftJournalBoundary) throws -> Void) async throws -> Receipt.Snapshot {
        guard expected.value.phase == .preparing else { throw SharedMediaStorageFailure.closed }
        let next = try preparationSuccessor(expected.value, phase: .abortingPreparation)
        return try await persist(next, replacing: expected, container: container, authority: authority, files: files,
            availableBytes: availableBytes, boundary: boundary, discharge: false, cleanupTarget: cleanupTarget)
    }

    static func finishPreparationAbort(_ expected: Receipt.Snapshot, container: ModelContainer,
                                       authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                                       availableBytes: () throws -> Int64,
                                       boundary: (SharedMediaCaptureDraftJournalBoundary) throws -> Void) async throws -> Receipt.Snapshot {
        guard expected.value.phase == .abortingPreparation else { throw SharedMediaStorageFailure.closed }
        try SharedMediaCapturePreparationAbort.requireReleased(expected, container: container)
        var next = try preparationSuccessor(expected.value, phase: .editing)
        next.abortedPreparations = (expected.value.abortedPreparations ?? [])
            + [try SharedMediaCapturePreparationAbort.tombstone(expected, container: container)]
        return try await persist(next, replacing: expected, container: container, authority: authority, files: files,
            availableBytes: availableBytes, boundary: boundary, discharge: true)
    }

    static func preparationSuccessor(_ previous: Journal, phase: Journal.Phase) throws -> Journal {
        guard (previous.phase == .preparing && phase == .abortingPreparation)
            || (previous.phase == .abortingPreparation && phase == .editing) else { throw SharedMediaStorageFailure.closed }
        return Journal(format: previous.format, profile: previous.profile, rootBindingSHA256: previous.rootBindingSHA256,
            scanID: previous.scanID, generation: previous.generation, revision: try SharedMediaStoragePolicy.add(previous.revision, 1),
            phase: phase, sources: previous.sources, items: previous.items, frozenObservation: nil, frozenContext: nil,
            preparation: phase == .abortingPreparation ? previous.preparation : nil,
            abortedPreparations: previous.abortedPreparations)
    }

    /// Finish an entire item's discard only after every reserved original has
    /// retired. An unreserved member receives a distinct durable tombstone;
    /// generic editing cannot manufacture that acknowledgement.
    static func finishDiscard(itemID: UUID, expected: Receipt.Snapshot, container: ModelContainer,
                              authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                              availableBytes: () throws -> Int64,
                              boundary: (SharedMediaCaptureDraftJournalBoundary) throws -> Void = { _ in }) async throws -> Receipt.Snapshot {
        let previous = expected.value
        guard previous.phase == .editing || previous.phase == .discarding,
              previous.profile == authority.profile, previous.rootBindingSHA256 == files.rootBindingSHA256 else {
            throw SharedMediaStorageFailure.closed
        }
        let read = ModelContext(container); read.autosaveEnabled = false
        var members = previous.sources
        let indices = members.indices.filter { members[$0].itemID == itemID }
        guard !indices.isEmpty else { throw SharedMediaStorageFailure.conflict }
        for index in indices {
            guard members[index].state == .discarding else { throw SharedMediaStorageFailure.closed }
            let id = members[index].input.id, mediaID = members[index].input.mediaID
            var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id || $0.mediaID == mediaID })
            query.fetchLimit = 2
            let rows = try read.fetch(query)
            guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            if let row = rows.first {
                let artifact = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
                guard try SharedMediaCaptureDraftSourceInput(retained: artifact.request) == members[index].input,
                      artifact.retirement?.releasedRevision != nil else { throw SharedMediaStorageFailure.closed }
                members[index].state = .released
            } else { members[index].state = .releasedWithoutReservationV1 }
        }
        let allReleased = members.allSatisfy { $0.state.isTerminal }
        // Notes supplement media; removing the final media clears the whole
        // composition in this same durable acknowledgement.
        let items = allReleased ? [] : previous.items.filter { $0.id != itemID }
        let phase: Journal.Phase = allReleased ? .released : previous.phase
        let next = Journal(format: previous.format, profile: previous.profile, rootBindingSHA256: previous.rootBindingSHA256,
            scanID: previous.scanID, generation: previous.generation, revision: try SharedMediaStoragePolicy.add(previous.revision, 1),
            phase: phase, sources: members, items: items, frozenObservation: nil, frozenContext: nil,
            abortedPreparations: previous.abortedPreparations)
        // persist performs the complete physical/graph audit, then a fresh
        // header + exact journal CAS and absence check before its only save.
        return try await persist(next, replacing: expected, container: container, authority: authority, files: files,
            availableBytes: availableBytes, boundary: boundary, discharge: true)
    }

    private static func persist(_ next: Journal, replacing expected: Receipt.Snapshot?, container: ModelContainer,
                                authority: SharedMediaNativeAppOperationAuthority, files: SharedMediaCaptureArtifactFiles,
                                availableBytes: () throws -> Int64,
                                boundary: (SharedMediaCaptureDraftJournalBoundary) throws -> Void,
                                discharge: Bool, cleanupTarget: UUID? = nil) async throws -> Receipt.Snapshot {
        let bytes = try next.encoded(), digest = SharedMediaAcquisitionEncoding.digest(bytes)
        guard next.profile == authority.profile, next.rootBindingSHA256 == files.rootBindingSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
        let before = try authority.header(container)
        var totals = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files, cleanupTarget: cleanupTarget)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        let current = try Receipt.matching(scanID: next.scanID, generation: next.generation, context: context)
        if let current, current.bytes == bytes, current.sha256 == digest { return current }
        guard current == expected else { throw SharedMediaStorageFailure.stale }
        if !discharge { try requireTransition(from: expected?.value, to: next) }
        let parent = try SharedMediaCaptureSubmissionReceipt.matching(scanID: next.scanID, generation: next.generation, in: context)
        try Receipt.requireGraph(.init(value: next, bytes: bytes, sha256: digest), parent: parent, context: context)
        if expected == nil {
            let scan = next.scanID, generation = next.generation
            var artifacts = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate {
                $0.recipientScanID == scan || $0.submissionGeneration == generation
            })
            artifacts.fetchLimit = 1
            guard try context.fetch(artifacts).isEmpty else { throw SharedMediaStorageFailure.conflict }
            let reserved = Int64(Journal.maximumBytes + 64)
            try totals.includePhotoPackage(id: next.scanID, bytes: reserved)
            try totals.includePhotoPhysical(materialized: 0, reserved: reserved)
        }
        try totals.checkAvailable(availableBytes())
        let inventoryID = authority.profile.inventoryID
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard inventory.revision == before.inventory.revision,
              try SharedMediaNativeAppEligibility.profile(inventory) == authority.profile else { throw SharedMediaStorageFailure.stale }
        let row: SharedMediaCaptureDraftJournalRecord
        if expected != nil {
            let generation = next.generation
            row = try one(context, FetchDescriptor<SharedMediaCaptureDraftJournalRecord>(predicate: #Predicate { $0.id == generation }))
            row.revision = next.revision; row.bodyData = bytes; row.bodySHA256 = digest
        } else {
            row = .init(generation: next.generation, inventoryID: inventoryID, inventoryGeneration: next.profile.generation,
                ownerID: next.profile.ownerID, scanID: next.scanID, rootBindingSHA256: next.rootBindingSHA256,
                bodyData: bytes, bodySHA256: digest)
            context.insert(row)
        }
        inventory.revision = try SharedMediaStoragePolicy.add(before.inventory.revision, 1)
        try boundary(.beforeSave); try files.check()
        guard try authority.header(container) == before,
              try Receipt.matching(scanID: next.scanID, generation: next.generation, context: ModelContext(container)) == expected else {
            throw SharedMediaStorageFailure.stale
        }
        // Only these two records may be changed by this operation.
        let allowed = Set([row.persistentModelID, inventory.persistentModelID])
        guard context.deletedModelsArray.isEmpty,
              Set(context.insertedModelsArray.map(\.persistentModelID) + context.changedModelsArray.map(\.persistentModelID)).isSubset(of: allowed) else {
            throw SharedMediaStorageFailure.conflict
        }
        func readback() throws -> Receipt.Snapshot {
            try files.check()
            let header = try authority.header(container)
            guard header == (try SharedMediaNativeAppMetadataFacts.successor(before)) else { throw SharedMediaStorageFailure.stale }
            let read = ModelContext(container); read.autosaveEnabled = false
            guard let saved = try Receipt.matching(scanID: next.scanID, generation: next.generation, context: read),
                  saved.bytes == bytes, saved.sha256 == digest else { throw SharedMediaStorageFailure.conflict }
            return saved
        }
        do {
            try context.save(); try boundary(.afterSave); try boundary(.beforeReadback)
            return try readback()
        } catch {
            let failure = error; context.rollback()
            // Read-only recovery cannot perform a second save after uncertainty.
            do { try boundary(.beforeReadback); return try readback() } catch { throw failure }
        }
    }

    private static func requireTransition(from previous: Journal?, to next: Journal) throws {
        guard next.frozenObservation == nil, next.frozenContext == nil else { throw SharedMediaStorageFailure.closed }
        guard let previous else {
            guard next.phase == .editing, next.revision == 0, next.abortedPreparations == nil,
                  next.sources.allSatisfy({ $0.state == .pending }) else { throw SharedMediaStorageFailure.conflict }
            return
        }
        guard previous.profile == next.profile, previous.rootBindingSHA256 == next.rootBindingSHA256,
              previous.scanID == next.scanID, previous.generation == next.generation,
              next.revision == previous.revision + 1, next.abortedPreparations == previous.abortedPreparations else { throw SharedMediaStorageFailure.stale }
        switch (previous.phase, next.phase) {
        case (.preparing, .abortingPreparation):
            guard previous.sources == next.sources, previous.items == next.items,
                  previous.preparation == next.preparation else { throw SharedMediaStorageFailure.conflict }
        case (.editing, .preparing):
            guard previous.sources == next.sources, previous.items == next.items,
                  next.preparation?.previousJournalSHA256 == (try SharedMediaAcquisitionEncoding.digest(previous.encoded())) else {
                throw SharedMediaStorageFailure.conflict
            }
        case (.editing, .editing), (.editing, .discarding), (.discarding, .discarding), (.discarding, .released): break
        default: throw SharedMediaStorageFailure.closed
        }
        for old in previous.sources {
            guard let new = next.sources.first(where: { $0.input.id == old.input.id }),
                  new.input == old.input, new.itemID == old.itemID else { throw SharedMediaStorageFailure.conflict }
            switch (old.state, new.state) {
            case (.pending, .pending), (.pending, .ready), (.pending, .discarding), (.ready, .ready),
                 (.ready, .discarding), (.discarding, .discarding), (.discarding, .released), (.released, .released),
                 (.releasedWithoutReservationV1, .releasedWithoutReservationV1): break
            default: throw SharedMediaStorageFailure.conflict
            }
        }
        let oldIDs = Set(previous.sources.map { $0.input.id })
        guard next.sources.filter({ !oldIDs.contains($0.input.id) }).allSatisfy({ $0.state == .pending && previous.phase == .editing && next.phase == .editing }) else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}
