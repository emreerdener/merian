import Foundation
import SwiftData

/// Discovery carries canonical review state, never file or submission authority.
/// Audit the entire root before filtering terminal rows so corrupt/foreign work
/// cannot disappear from recovery behind a cursor or phase filter.
@MainActor
enum SharedMediaCaptureDraftJournalRecovery {
    struct Page: Equatable, Sendable {
        let drafts: [SharedMediaCaptureDraftJournalReceipt.Snapshot]
        let nextCursor: String?
    }
    static let pageSize = 16

    /// A source can have committed its bytes just before the journal's ready
    /// acknowledgement was interrupted. Promote only that exact audited row;
    /// a reserved/writing/absent member remains pending and grants no read.
    static func recoverReady(_ expected: SharedMediaCaptureDraftJournalReceipt.Snapshot,
                             container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                             files: SharedMediaCaptureArtifactFiles,
                             availableBytes: () throws -> Int64,
                             boundary: (SharedMediaCaptureDraftJournalBoundary) throws -> Void = { _ in }) async throws -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let value = expected.value
        let context = ModelContext(container); context.autosaveEnabled = false
        guard value.phase == .editing, value.profile == authority.profile,
              value.rootBindingSHA256 == files.rootBindingSHA256,
              try SharedMediaCaptureDraftJournalReceipt.matching(scanID: value.scanID,
                generation: value.generation, context: context) == expected else { throw SharedMediaStorageFailure.stale }
        var sources = value.sources
        for index in sources.indices where sources[index].state == .pending {
            let input = sources[index].input, id = input.id, media = input.mediaID
            var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id || $0.mediaID == media })
            query.fetchLimit = 2
            let rows = try context.fetch(query)
            guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            guard let row = rows.first else { continue }
            let artifact = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
            guard artifact.retirement == nil, artifact.remoteStage == nil,
                  artifact.request.profile == value.profile, artifact.request.rootBindingSHA256 == value.rootBindingSHA256,
                  try SharedMediaCaptureDraftSourceInput(retained: artifact.request) == input else { throw SharedMediaStorageFailure.conflict }
            if artifact.phase == .ready { sources[index].state = .ready }
        }
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        guard sources != value.sources else { return expected }
        let recovered = SharedMediaCaptureDraftJournal(format: value.format, profile: value.profile,
            rootBindingSHA256: value.rootBindingSHA256, scanID: value.scanID, generation: value.generation,
            revision: try SharedMediaStoragePolicy.add(value.revision, 1), phase: .editing,
            sources: sources, items: value.items, frozenObservation: nil, frozenContext: nil, abortedPreparations: value.abortedPreparations)
        return try await SharedMediaCaptureDraftJournalStore.saveEditing(recovered, replacing: expected,
            container: container, authority: authority, files: files, availableBytes: availableBytes, boundary: boundary)
    }

    static func page(after cursor: String?, container: ModelContainer,
                     authority: SharedMediaNativeAppOperationAuthority,
                     files: SharedMediaCaptureArtifactFiles) async throws -> Page {
        if let cursor {
            guard let id = UUID(uuidString: cursor), id.uuidString.lowercased() == cursor else {
                throw SharedMediaStorageFailure.invalid
            }
        }
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        var query: FetchDescriptor<SharedMediaCaptureDraftJournalRecord>
        if let cursor {
            query = .init(predicate: #Predicate { $0.cursorKey > cursor }, sortBy: [SortDescriptor(\.cursorKey)])
        } else { query = .init(sortBy: [SortDescriptor(\.cursorKey)]) }
        query.fetchLimit = pageSize + 1
        let rows = try context.fetch(query)
        var drafts: [SharedMediaCaptureDraftJournalReceipt.Snapshot] = []
        for row in rows.prefix(pageSize) {
            try Task.checkCancellation()
            let saved = try SharedMediaCaptureDraftJournalReceipt.decode(row)
            guard saved.value.profile == authority.profile,
                  saved.value.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
            let parent = try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: saved.value.scanID,
                generation: saved.value.generation, in: context)
            try SharedMediaCaptureDraftJournalReceipt.requireGraph(saved, parent: parent, context: context)
            if saved.value.phase != .released { drafts.append(saved) }
        }
        try files.check()
        guard try authority.header(container) == before, !context.hasChanges else { throw SharedMediaStorageFailure.stale }
        return .init(drafts: drafts, nextCursor: rows.count > pageSize ? rows[pageSize - 1].cursorKey : nil)
    }
}
