import Foundation
import SwiftData

/// Canonical journal readback and reverse membership audit. These values grant
/// no file access; callers retain the registered root and account fence.
@MainActor
enum SharedMediaCaptureDraftJournalReceipt {
    struct Snapshot: Equatable, Sendable {
        let value: SharedMediaCaptureDraftJournal
        let bytes: Data
        let sha256: String
        var metadataBytes: Int64 { Int64(bytes.count + 64) }
        var futureBytes: Int64 {
            value.phase == .released ? 0 : Int64(SharedMediaCaptureDraftJournal.maximumBytes - bytes.count)
        }
    }
    struct Inventory {
        var entryCount: Int64 = 0
        var metadata: Int64 = 0
        var future: Int64 = 0
        var pending: Set<UUID> = []
        var packages: [UUID: Int64] = [:]
    }

    static func decode(_ row: SharedMediaCaptureDraftJournalRecord) throws -> Snapshot {
        let value = try SharedMediaCaptureDraftJournal.decode(row.bodyData, sha256: row.bodySHA256)
        guard row.schemaVersion == 1, row.id == value.generation,
              row.cursorKey == value.generation.uuidString.lowercased(),
              row.scanKey == [value.profile.ownerID, value.scanID].map({ $0.uuidString.lowercased() }).joined(separator: ":"),
              row.inventoryID == value.profile.inventoryID, row.inventoryGeneration == value.profile.generation,
              row.ownerID == value.profile.ownerID, row.scanID == value.scanID,
              row.rootBindingSHA256 == value.rootBindingSHA256, row.revision == value.revision else {
            throw SharedMediaStorageFailure.conflict
        }
        return .init(value: value, bytes: row.bodyData, sha256: row.bodySHA256)
    }

    static func matching(scanID: UUID, generation: UUID, context: ModelContext) throws -> Snapshot? {
        var query = FetchDescriptor<SharedMediaCaptureDraftJournalRecord>(predicate: #Predicate {
            $0.scanID == scanID || $0.id == generation
        })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let row = rows.first else { return nil }
        let saved = try decode(row)
        guard saved.value.scanID == scanID, saved.value.generation == generation else { throw SharedMediaStorageFailure.conflict }
        return saved
    }

    static func requireSource(_ input: SharedMediaCaptureDraftSourceInput, states: Set<SharedMediaCaptureDraftJournal.SourceState>,
                              phases: Set<SharedMediaCaptureDraftJournal.Phase>, context: ModelContext) throws {
        guard let saved = try matching(scanID: input.scanID, generation: input.submissionGeneration, context: context) else { return }
        guard phases.contains(saved.value.phase),
              let source = saved.value.sources.first(where: { $0.input.id == input.id }),
              source.input == input, states.contains(source.state) else { throw SharedMediaStorageFailure.closed }
    }

    /// Deliberately visits every row, including foreign/corrupt scope and empty
    /// pending drafts. A malformed row cannot disappear behind a scope filter.
    static func inventory(context: ModelContext, profile: SharedMediaNativeAppProfile,
                          rootBindingSHA256: String, checkpoint: () throws -> Void) throws -> Inventory {
        var result = Inventory(), offset = 0
        var query = FetchDescriptor<SharedMediaCaptureDraftJournalRecord>(sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        while true {
            try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows {
                try checkpoint()
                let saved = try decode(row), value = saved.value
                guard value.profile == profile, value.rootBindingSHA256 == rootBindingSHA256 else {
                    throw SharedMediaStorageFailure.conflict
                }
                let parent = try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: value.scanID,
                    generation: value.generation, in: context)
                try requireGraph(saved, parent: parent, context: context)
                result.entryCount = try SharedMediaStoragePolicy.add(result.entryCount, 1)
                result.metadata = try SharedMediaStoragePolicy.add(result.metadata, saved.metadataBytes)
                result.future = try SharedMediaStoragePolicy.add(result.future, saved.futureBytes)
                if value.phase != .accepted && value.phase != .released { result.pending.insert(value.generation) }
                if parent == nil && value.phase != .released {
                    guard result.packages.updateValue(try SharedMediaStoragePolicy.add(saved.metadataBytes, saved.futureBytes),
                        forKey: value.scanID) == nil else { throw SharedMediaStorageFailure.conflict }
                    guard result.packages.count <= PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
                }
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        try checkpoint()
        return result
    }

    static func requireGraph(_ saved: Snapshot, parent: SharedMediaCaptureSubmissionReceipt.Snapshot?, context: ModelContext) throws {
        let value = saved.value
        try SharedMediaCaptureAbortedPreparation.requireMembers(value, context: context)
        switch value.phase {
        case .editing, .preparing, .abortingPreparation, .discarding, .released:
            guard parent == nil else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: value.scanID, context: context)
        case .submitting, .accepted:
            if let parent {
                guard parent.submission.profile == value.profile,
                      parent.submission.rootBindingSHA256 == value.rootBindingSHA256,
                      parent.submission.observation == value.frozenObservation,
                      parent.submission.context == value.frozenContext else { throw SharedMediaStorageFailure.conflict }
                switch (value.phase, parent.state) {
                case (.submitting, .reserved), (.accepted, .accepted): break
                default: throw SharedMediaStorageFailure.conflict
                }
            } else { throw SharedMediaStorageFailure.conflict }
        }
        for source in value.sources {
            let id = source.input.id, media = source.input.mediaID
            var query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.id == id || $0.mediaID == media })
            query.fetchLimit = 2
            let rows = try context.fetch(query)
            guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            guard let row = rows.first else {
                guard source.state == .pending || source.state == .discarding || source.state == .releasedWithoutReservationV1 else {
                    throw SharedMediaStorageFailure.conflict
                }
                continue
            }
            let artifact = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
            guard try SharedMediaCaptureDraftSourceInput(retained: artifact.request) == source.input,
                  artifact.request.profile == value.profile,
                  artifact.request.rootBindingSHA256 == value.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
            switch source.state {
            case .pending:
                guard artifact.retirement == nil, artifact.remoteStage == nil else { throw SharedMediaStorageFailure.conflict }
            case .ready:
                guard artifact.phase == .ready, artifact.retirement == nil else { throw SharedMediaStorageFailure.conflict }
            case .discarding:
                guard artifact.remoteStage == nil else { throw SharedMediaStorageFailure.conflict }
            case .released:
                guard artifact.retirement?.releasedRevision != nil else { throw SharedMediaStorageFailure.conflict }
            case .releasedWithoutReservationV1:
                throw SharedMediaStorageFailure.conflict
            }
        }
    }
}
