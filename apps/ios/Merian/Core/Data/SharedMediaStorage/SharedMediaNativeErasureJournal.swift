import Foundation
import SwiftData

/// Cleanup-only journal transactions. The caller must retain the accepted outer
/// operation, drained runtime, store fence and physical root locks throughout.
/// `checkpoint` revalidates those capabilities; these rows do not mint them.
@MainActor
enum SharedMediaNativeErasureJournal {
    typealias Header = SharedMediaNativeErasureHeader
    typealias State = SharedMediaNativeLibraryErasureState
    typealias Row = SharedMediaNativeErasurePageRecord
    typealias Manifest = SharedMediaNativeErasureManifest
    enum Boundary: CaseIterable { case beforeSave, afterSave, beforeReadback }

    struct Snapshot: Equatable {
        let header: Header
        let state: State
        let pages: Int64
        let entries: Int64
        let lastSHA256: String?
        var hasCompleteManifest: Bool {
            pages == header.pageCount && entries == header.entryCount && lastSHA256 == header.lastPageSHA256
        }
    }

    static func read(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                     operationID: UUID, checkpoint: () throws -> Void) throws -> Snapshot {
        try checkpoint()
        let context = try clean(container)
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>())
        guard try SharedMediaNativeAppEligibility.profileAssertion(inventory) == profile else { throw SharedMediaStorageFailure.conflict }
        let state = try State.read(inventory)
        guard state.id == operationID else { throw SharedMediaStorageFailure.conflict }
        let row = try one(context, FetchDescriptor<Row>(predicate: #Predicate { $0.kindRaw == "header" }))
        try requireRow(row, profile: profile, state: state, kind: "header", ordinal: 0)
        let header = try Header.decode(row.bodyData, profile: profile)
        guard header.operationID == operationID, header.sourceRevision == state.sourceRevision,
              row.bodySHA256 == state.manifestSHA256 else { throw SharedMediaStorageFailure.conflict }
        var chain = Manifest.Chain(operationID: operationID, profile: profile)
        var query = FetchDescriptor<Row>(predicate: #Predicate { $0.kindRaw == "page" }, sortBy: [SortDescriptor(\.ordinal)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0
        while true {
            try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for page in rows {
                try requireRow(page, profile: profile, state: state, kind: "page", ordinal: chain.pageCount)
                _ = try chain.consume(page.bodyData)
                guard chain.pageCount <= header.pageCount, chain.entryCount <= header.entryCount else { throw SharedMediaStorageFailure.conflict }
            }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
        }
        guard Int64(try context.fetchCount(FetchDescriptor<Row>())) == chain.pageCount + 1 else { throw SharedMediaStorageFailure.conflict }
        let result = Snapshot(header: header, state: state, pages: chain.pageCount,
            entries: chain.entryCount, lastSHA256: chain.digest)
        if state.stage != .preparing || result.pages == header.pageCount {
            guard result.hasCompleteManifest else { throw SharedMediaStorageFailure.conflict }
        }
        let graph = try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: checkpoint)
        if state.stage == .cleared {
            guard graph.allSatisfy({ $0.rows == 0 }) else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard graph == header.sourceTables else { throw SharedMediaStorageFailure.stale }
        }
        try checkpoint()
        let fresh = try clean(container)
        guard try State.read(one(fresh, FetchDescriptor<SharedMediaInventoryRecord>())) == state else { throw SharedMediaStorageFailure.stale }
        return result
    }

    /// Header and non-ready inventory phase commit in one save. A crash can
    /// never leave a ready inventory with a partial manifest to be adopted.
    static func begin(_ header: Header, container: ModelContainer, profile: SharedMediaNativeAppProfile,
                      checkpoint: () throws -> Void, boundary: (Boundary) throws -> Void = { _ in }) throws -> Snapshot {
        try checkpoint()
        let bytes = try header.encoded(profile: profile), context = try clean(container)
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>())
        guard try SharedMediaNativeAppEligibility.profile(inventory) == profile,
              inventory.revision == header.sourceRevision,
              try context.fetchCount(FetchDescriptor<Row>()) == 0,
              try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: checkpoint) == header.sourceTables else {
            throw SharedMediaStorageFailure.conflict
        }
        let state = try State.intent(id: header.operationID, profile: profile,
            manifestSHA256: SharedMediaAcquisitionEncoding.digest(bytes), sourceRevision: header.sourceRevision)
        try checkpoint()
        context.insert(makeRow(bytes, kind: "header", ordinal: 0, profile: profile, state: state))
        inventory.phaseRaw = state.phase; inventory.cursor = try state.encoded(); inventory.revision = state.revision
        let expected = Snapshot(header: header, state: state, pages: 0, entries: 0, lastSHA256: nil)
        return try save(context, expected: expected, profile: profile, checkpoint: checkpoint, boundary: boundary)
    }

    /// Exact prefix replay is idempotent. A different body at an existing
    /// ordinal, a gap, a foreign operation or an unknown carrier is rejected.
    static func append(_ bytes: Data, container: ModelContainer, profile: SharedMediaNativeAppProfile,
                       operationID: UUID, checkpoint: () throws -> Void,
                       boundary: (Boundary) throws -> Void = { _ in }) throws -> Snapshot {
        let before = try read(container: container, profile: profile, operationID: operationID, checkpoint: checkpoint)
        guard before.state.stage == .preparing else { throw SharedMediaStorageFailure.closed }
        let page = try Manifest.Page.decode(bytes, profile: profile)
        guard page.operationID == operationID else { throw SharedMediaStorageFailure.conflict }
        let context = try clean(container), ordinal = page.ordinal
        if ordinal < before.pages {
            let row = try one(context, FetchDescriptor<Row>(predicate: #Predicate { $0.kindRaw == "page" && $0.ordinal == ordinal }))
            guard row.bodyData == bytes else { throw SharedMediaStorageFailure.conflict }
            try checkpoint(); return before
        }
        guard ordinal == before.pages, ordinal < before.header.pageCount,
              page.previousSHA256 == before.lastSHA256 else { throw SharedMediaStorageFailure.conflict }
        // A full chain readback also checks cross-page lexical order, totals and
        // the final digest. Check these before saving so invalid input is inert.
        if ordinal > 0 {
            let previousOrdinal = ordinal - 1
            let previous = try one(context, FetchDescriptor<Row>(predicate: #Predicate { $0.kindRaw == "page" && $0.ordinal == previousOrdinal }))
            let last = try Manifest.Page.decode(previous.bodyData, profile: profile)
            guard let key = last.entries.last?.key, key < page.entries[0].key else { throw SharedMediaStorageFailure.conflict }
        }
        let expected = Snapshot(header: before.header, state: before.state, pages: ordinal + 1,
            entries: try SharedMediaStoragePolicy.add(before.entries, Int64(page.entries.count)),
            lastSHA256: SharedMediaAcquisitionEncoding.digest(bytes))
        guard expected.entries <= before.header.entryCount,
              expected.pages != before.header.pageCount || expected.hasCompleteManifest else { throw SharedMediaStorageFailure.conflict }
        try checkpoint()
        context.insert(makeRow(bytes, kind: "page", ordinal: ordinal, profile: profile, state: before.state))
        return try save(context, expected: expected, profile: profile, checkpoint: checkpoint, boundary: boundary)
    }

    static func retire(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                       checkpoint: () throws -> Void, boundary: (Boundary) throws -> Void = { _ in }) throws -> Snapshot {
        let before = try read(container: container, profile: profile, operationID: operationID, checkpoint: checkpoint)
        guard before.hasCompleteManifest else { throw SharedMediaStorageFailure.conflict }
        if before.state.stage == .retiring { return before }
        let state = try before.state.retiring(), context = try clean(container)
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>())
        guard try State.read(inventory) == before.state else { throw SharedMediaStorageFailure.stale }
        try checkpoint()
        inventory.phaseRaw = state.phase; inventory.cursor = try state.encoded(); inventory.revision = state.revision
        return try save(context, expected: .init(header: before.header, state: state, pages: before.pages,
            entries: before.entries, lastSHA256: before.lastSHA256), profile: profile, checkpoint: checkpoint, boundary: boundary)
    }

    /// Physical retirement must be proven under the caller's still-held root
    /// descriptors. A database phase alone is never an absence witness.
    static func complete(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                         checkpoint: () throws -> Void, absence: SharedMediaNativeErasureAbsence,
                         boundary: (Boundary) throws -> Void = { _ in }) throws -> Snapshot {
        try complete(container: container, profile: profile, operationID: operationID, checkpoint: checkpoint,
            verifyAbsence: { try absence.require($0, profile: profile) }, boundary: boundary)
    }

    private static func complete(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                                 checkpoint: () throws -> Void, verifyAbsence: (Header) throws -> Void,
                                 boundary: (Boundary) throws -> Void = { _ in }) throws -> Snapshot {
        let before = try read(container: container, profile: profile, operationID: operationID, checkpoint: checkpoint)
        guard before.hasCompleteManifest,
              before.state.stage == .retiring || before.state.stage == .complete else { throw SharedMediaStorageFailure.closed }
        try verifyAbsence(before.header); try checkpoint()
        if before.state.stage == .complete { return before }
        let state = try before.state.completed(), context = try clean(container)
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>())
        guard try State.read(inventory) == before.state else { throw SharedMediaStorageFailure.stale }
        inventory.phaseRaw = state.phase; inventory.cursor = try state.encoded(); inventory.revision = state.revision
        return try save(context, expected: .init(header: before.header, state: state, pages: before.pages,
            entries: before.entries, lastSHA256: before.lastSHA256), profile: profile,
            checkpoint: { try checkpoint(); try verifyAbsence(before.header) }, boundary: boundary)
    }

    /// All source rows and the cleared cursor commit together. Keep the
    /// immutable manifest and inventory until an independent terminal receipt
    /// survives generic library/preferences cleanup and cold restart.
    static func clearSourceRows(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                                checkpoint: () throws -> Void, absence: SharedMediaNativeErasureAbsence,
                                boundary: (Boundary) throws -> Void = { _ in }) throws -> Snapshot {
        try clearSourceRows(container: container, profile: profile, operationID: operationID, checkpoint: checkpoint,
            verifyAbsence: { try absence.require($0, profile: profile) }, boundary: boundary)
    }

    private static func clearSourceRows(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                                        checkpoint: () throws -> Void, verifyAbsence: (Header) throws -> Void,
                                        boundary: (Boundary) throws -> Void = { _ in }) throws -> Snapshot {
        let before = try read(container: container, profile: profile, operationID: operationID, checkpoint: checkpoint)
        guard before.hasCompleteManifest,
              before.state.stage == .complete || before.state.stage == .cleared else { throw SharedMediaStorageFailure.closed }
        try verifyAbsence(before.header); try checkpoint()
        if before.state.stage == .cleared { return before }
        let state = try before.state.cleared(), context = try clean(container)
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>())
        guard try State.read(inventory) == before.state else { throw SharedMediaStorageFailure.stale }
        do {
            for type in SharedMediaNativeErasureGraph.modelTypes {
                try checkpoint()
                try stageDeletion(type, in: context, checkpoint: checkpoint)
            }
            inventory.phaseRaw = state.phase; inventory.cursor = try state.encoded(); inventory.revision = state.revision
            return try save(context, expected: .init(header: before.header, state: state, pages: before.pages,
                entries: before.entries, lastSHA256: before.lastSHA256), profile: profile,
                checkpoint: { try checkpoint(); try verifyAbsence(before.header) }, boundary: boundary)
        } catch {
            context.rollback(); throw error
        }
    }

    private static func stageDeletion<T: PersistentModel>(_ type: T.Type, in context: ModelContext,
                                                          checkpoint: () throws -> Void) throws {
        // Store-level bulk deletion can escape a later context rollback. Stage
        // individual model rows instead, so source deletion and cursor share the
        // single save. model(for:) futures cannot safely be deleted by SwiftData.
        var query = FetchDescriptor<T>(sortBy: [SortDescriptor(\.persistentModelID)])
        query.includePendingChanges = false
        let expectedCount = try context.fetchCount(query)
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0
        var lastID: PersistentIdentifier?
        while true {
            try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows {
                let id = row.persistentModelID
                guard lastID.map({ $0 < id }) ?? true else { throw SharedMediaStorageFailure.conflict }
                lastID = id
                context.delete(row)
            }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
        }
        guard offset == expectedCount else { throw SharedMediaStorageFailure.stale }
    }

    /// The durable parent receipt must survive before the final same-store
    /// carrier disappears. Its proof rechecks physical absence without reading
    /// the soon-to-be-deleted manifest. Ambiguous save uses a distinct zero-row
    /// readback, never a missing journal as evidence of success.
    static func retireCarrier(container: ModelContainer, profile: SharedMediaNativeAppProfile, header: Header,
                              terminal: SharedMediaNativeErasureTerminal, checkpoint: () throws -> Void,
                              boundary: (Boundary) throws -> Void = { _ in }) throws {
        func readback() throws {
            try checkpoint(); try terminal.require(header, profile: profile)
            try boundary(.beforeReadback)
            try requireNoNativeRows(container: container, checkpoint: checkpoint)
            try terminal.require(header, profile: profile); try checkpoint()
        }
        let context = try clean(container)
        if try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0 {
            try readback(); return
        }
        let before = try read(container: container, profile: profile, operationID: header.operationID, checkpoint: checkpoint)
        guard before.header == header, before.state.stage == .cleared, before.hasCompleteManifest else {
            throw SharedMediaStorageFailure.conflict
        }
        try terminal.require(header, profile: profile)
        do {
            try stageDeletion(Row.self, in: context, checkpoint: checkpoint)
            context.delete(try one(context, FetchDescriptor<SharedMediaInventoryRecord>()))
            try checkpoint(); try terminal.require(header, profile: profile)
            try boundary(.beforeSave); try context.save(); try boundary(.afterSave)
            try readback()
        } catch {
            let failure = error; context.rollback()
            do { try readback() } catch { throw failure }
        }
    }

    static func requireNoNativeRows(container: ModelContainer, checkpoint: () throws -> Void) throws {
        try checkpoint()
        let context = try clean(container)
        guard try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 0,
              try context.fetchCount(FetchDescriptor<Row>()) == 0,
              try SharedMediaNativeErasureGraph.snapshot(context, checkpoint: checkpoint).allSatisfy({ $0.rows == 0 }) else {
            throw SharedMediaStorageFailure.conflict
        }
        try checkpoint()
    }

    /// Bounded immutable page reader for physical replay, including during the
    /// source-row transaction. Preparing never grants physical replay. Completed
    /// and cleared phases allow absence readback; only retiring permits unlink.
    static func visitManifest(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                              header: Header, removing: Bool, checkpoint: () throws -> Void, body: (Data) throws -> Void) throws {
        let context = try clean(container), bytes = try header.encoded(profile: profile)
        let state = try State.read(one(context, FetchDescriptor<SharedMediaInventoryRecord>()))
        guard state.stage != .preparing, !removing || state.stage == .retiring,
              state.id == header.operationID, state.manifestSHA256 == SharedMediaAcquisitionEncoding.digest(bytes) else {
            throw SharedMediaStorageFailure.conflict
        }
        let saved = try one(context, FetchDescriptor<Row>(predicate: #Predicate { $0.kindRaw == "header" }))
        try requireRow(saved, profile: profile, state: state, kind: "header", ordinal: 0)
        guard saved.bodyData == bytes else { throw SharedMediaStorageFailure.conflict }
        var chain = Manifest.Chain(operationID: header.operationID, profile: profile)
        for ordinal in 0..<header.pageCount {
            try checkpoint()
            let row = try one(context, FetchDescriptor<Row>(predicate: #Predicate { $0.kindRaw == "page" && $0.ordinal == ordinal }))
            try requireRow(row, profile: profile, state: state, kind: "page", ordinal: ordinal)
            _ = try chain.consume(row.bodyData); try body(row.bodyData)
        }
        try chain.requireComplete(pages: header.pageCount, entries: header.entryCount, lastSHA256: header.lastPageSHA256)
        guard try context.fetchCount(FetchDescriptor<Row>()) == header.pageCount + 1 else { throw SharedMediaStorageFailure.conflict }
        try checkpoint()
        let fresh = try clean(container)
        guard try State.read(one(fresh, FetchDescriptor<SharedMediaInventoryRecord>())) == state else {
            throw SharedMediaStorageFailure.stale
        }
    }

    #if DEBUG
    // Component transaction fault tests do not claim physical erasure. These
    // callbacks are unavailable to ordinary builds and require the test host.
    static func qualificationComplete(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                                      checkpoint: () throws -> Void, verifyAbsence: (Header) throws -> Void,
                                      boundary: (Boundary) throws -> Void) throws -> Snapshot {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try complete(container: container, profile: profile, operationID: operationID,
            checkpoint: checkpoint, verifyAbsence: verifyAbsence, boundary: boundary)
    }

    static func qualificationClear(container: ModelContainer, profile: SharedMediaNativeAppProfile, operationID: UUID,
                                   checkpoint: () throws -> Void, verifyAbsence: (Header) throws -> Void,
                                   boundary: (Boundary) throws -> Void) throws -> Snapshot {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try clearSourceRows(container: container, profile: profile, operationID: operationID,
            checkpoint: checkpoint, verifyAbsence: verifyAbsence, boundary: boundary)
    }
    #endif

    private static func save(_ context: ModelContext, expected: Snapshot, profile: SharedMediaNativeAppProfile,
                             checkpoint: () throws -> Void, boundary: (Boundary) throws -> Void) throws -> Snapshot {
        func readback() throws -> Snapshot {
            try boundary(.beforeReadback)
            let actual = try read(container: context.container, profile: profile, operationID: expected.state.id, checkpoint: checkpoint)
            guard actual == expected else { throw SharedMediaStorageFailure.stale }; return actual
        }
        do {
            try checkpoint(); try boundary(.beforeSave); try context.save(); try boundary(.afterSave)
            return try readback()
        } catch {
            let failure = error; context.rollback()
            // Ambiguous acknowledgement permits exact readback only, never a
            // second save or a newly minted cleanup operation.
            do { return try readback() } catch { throw failure }
        }
    }

    private static func requireRow(_ row: Row, profile: SharedMediaNativeAppProfile,
                                   state: State, kind: String, ordinal: Int64) throws {
        guard row.schemaVersion == 1, row.operationID == state.id, row.inventoryID == profile.inventoryID,
              row.inventoryGeneration == profile.generation, row.ownerID == profile.ownerID,
              row.profileSHA256 == state.profileSHA256, row.kindRaw == kind, row.ordinal == ordinal,
              row.cursorKey == "\(state.id.uuidString.lowercased()):\(kind):\(ordinal)",
              row.bodyData.count <= (kind == "header" ? Header.maximumBytes : Manifest.maximumPageBytes),
              SharedMediaAcquisitionEncoding.digest(row.bodyData) == row.bodySHA256 else { throw SharedMediaStorageFailure.conflict }
    }

    private static func makeRow(_ bytes: Data, kind: String, ordinal: Int64,
                                profile: SharedMediaNativeAppProfile, state: State) -> Row {
        .init(operationID: state.id, inventoryID: profile.inventoryID, inventoryGeneration: profile.generation,
            ownerID: profile.ownerID, profileSHA256: state.profileSHA256, kindRaw: kind, ordinal: ordinal,
            bodyData: bytes, bodySHA256: SharedMediaAcquisitionEncoding.digest(bytes))
    }

    private static func clean(_ container: ModelContainer) throws -> ModelContext {
        guard !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}
