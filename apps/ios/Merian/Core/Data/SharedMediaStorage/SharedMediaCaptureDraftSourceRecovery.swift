import Foundation
import SwiftData

/// Bounded discovery of pre-plan originals. Entries are descriptive snapshots;
/// the current owner must revalidate them before reading or changing a draft.
@MainActor
enum SharedMediaCaptureDraftSourceRecovery {
    struct Page: Equatable, Sendable {
        let sources: [SharedMediaCaptureArtifactLedger.Snapshot]
        let retirements: [SharedMediaCaptureDraftSourceInput]
        let nextCursor: String?
    }
    static let pageSize = 32

    struct Inventory {
        let artifactCount: Int64
        let generations: Set<UUID>
    }

    /// Reverse membership accounting shared by full-root qualification and the
    /// ordinary graph audit. Only canonical parentless sources may contribute;
    /// a generic orphan cannot be excused as an unfinished draft.
    static func unboundInventory(context: ModelContext, profile: SharedMediaNativeAppProfile,
                                 rootBindingSHA256: String, checkpoint: () throws -> Void) throws -> Inventory {
        var count: Int64 = 0, offset = 0
        var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchLimit = pageSize
        var scans: [UUID: UUID] = [:], generations: [UUID: UUID] = [:]
        while true {
            try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows {
                try checkpoint()
                let artifact = try SharedMediaCaptureArtifactLedger.auditReceipt(row), request = artifact.request
                if let retirement = artifact.retirement {
                    guard request.profile == profile,
                          request.rootBindingSHA256 == rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
                    if retirement.version == 2 {
                        try SharedMediaCaptureAbortedPreparation.requireRetirement(artifact, context: context)
                    }
                    if retirement.releasedRevision == nil { generations[request.submissionGeneration] = request.scanID }
                    count = try SharedMediaStoragePolicy.add(count, 1)
                    continue
                }
                if let parent = try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: request.scanID,
                    generation: request.submissionGeneration, in: context) {
                    guard parent.submission.scanID == request.scanID,
                          parent.submission.generation == request.submissionGeneration,
                          parent.artifacts.contains(artifact) else { throw SharedMediaStorageFailure.conflict }
                    continue
                }
                if request.format == .v1 {
                    try SharedMediaCapturePreparedAttempt.requireMember(request, context: context, phases: [.preparing, .abortingPreparation])
                }
                guard request.profile == profile,
                      request.rootBindingSHA256 == rootBindingSHA256, artifact.remoteStage == nil,
                      scans[request.scanID].map({ $0 == request.submissionGeneration }) ?? true,
                      generations[request.submissionGeneration].map({ $0 == request.scanID }) ?? true else {
                    throw SharedMediaStorageFailure.conflict
                }
                try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: request.scanID, context: context)
                scans[request.scanID] = request.submissionGeneration
                generations[request.submissionGeneration] = request.scanID
                count = try SharedMediaStoragePolicy.add(count, 1)
            }
            if rows.count < pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        try checkpoint()
        return .init(artifactCount: count, generations: Set(generations.keys))
    }

    static func read(_ expected: SharedMediaCaptureDraftSourceInput, container: ModelContainer,
                     authority: SharedMediaNativeAppOperationAuthority,
                     files: SharedMediaCaptureArtifactFiles) async throws -> Data {
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        try SharedMediaCaptureDraftJournalReceipt.requireSource(expected, states: [.ready], phases: [.editing, .preparing, .submitting, .accepted], context: context)
        let value = try SharedMediaCaptureArtifactLedger.read(id: expected.id, profile: authority.profile,
            rootBindingSHA256: files.rootBindingSHA256, context: context)
        guard try SharedMediaCaptureDraftSourceInput(retained: value.request) == expected,
              value.phase == .ready else { throw SharedMediaStorageFailure.conflict }
        return try await files.readReady(value, container: container, authority: authority)
    }

    static func page(after cursor: String?, container: ModelContainer,
                     authority: SharedMediaNativeAppOperationAuthority,
                     files: SharedMediaCaptureArtifactFiles) async throws -> Page {
        if let cursor {
            guard let id = UUID(uuidString: cursor), id.uuidString.lowercased() == cursor else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        let before = try authority.header(container)
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        let context = ModelContext(container); context.autosaveEnabled = false
        var query: FetchDescriptor<SharedMediaOrdinaryArtifactRecord>
        if let cursor {
            query = .init(predicate: #Predicate { $0.cursorKey > cursor }, sortBy: [SortDescriptor(\.cursorKey)])
        } else { query = .init(sortBy: [SortDescriptor(\.cursorKey)]) }
        query.fetchLimit = pageSize + 1
        let rows = try context.fetch(query)
        var sources: [SharedMediaCaptureArtifactLedger.Snapshot] = []
        var retirements: [SharedMediaCaptureDraftSourceInput] = []
        for row in rows.prefix(pageSize) {
            try Task.checkCancellation()
            let value = try SharedMediaCaptureArtifactLedger.auditRead(id: row.id, profile: authority.profile,
                rootBindingSHA256: files.rootBindingSHA256, context: context)
            let request = value.request
            if let retirement = value.retirement {
                if retirement.releasedRevision == nil, retirement.version == 1 { retirements.append(try .init(retained: request)) }
                continue
            }
            if try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: request.scanID,
                generation: request.submissionGeneration, in: context) != nil { continue }
            if request.format == .v1 {
                try SharedMediaCapturePreparedAttempt.requireMember(request, context: context, phases: [.preparing, .abortingPreparation])
                guard value.remoteStage == nil else { throw SharedMediaStorageFailure.conflict }
                continue
            }
            guard request.format == .draftSourceV1, value.remoteStage == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: request.scanID, context: context)
            sources.append(value)
        }
        try files.check()
        guard try authority.header(container) == before, !context.hasChanges else { throw SharedMediaStorageFailure.stale }
        return .init(sources: sources, retirements: retirements, nextCursor: rows.count > pageSize ? rows[pageSize - 1].cursorKey : nil)
    }
}

extension SharedMediaCaptureDraftSourceInput {
    init(retained request: SharedMediaCaptureArtifactRequest) throws {
        try request.validate()
        guard request.format == .draftSourceV1, let context = request.draftSource else {
            throw SharedMediaStorageFailure.conflict
        }
        self.init(id: request.id, scanID: request.scanID, submissionGeneration: request.submissionGeneration,
            mediaID: request.mediaID, itemIndex: request.itemIndex, role: request.role,
            contentType: request.contentType, byteCount: request.byteCount, sha256: request.sha256, context: context)
    }
}
