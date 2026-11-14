import Foundation
import SwiftData

/// The existing child owns its presentation budget. These transactions never
/// change execution metadata, attempts, selection, funding or media ownership.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
enum ObservationReanalysisRecoveryPresentationStore {
    typealias Value = AnalysisRecoveryPresentation
    private typealias Persistence = ObservationReanalysisPersistence

    struct Snapshot: Equatable, Sendable {
        let identity: OfflineQueueWork.Reanalysis
        let bytes: Data?
        let value: Value
        fileprivate init(identity: OfflineQueueWork.Reanalysis, bytes: Data?, value: Value) {
            self.identity = identity; self.bytes = bytes; self.value = value
        }
    }
    struct Interval: Sendable {
        let identity: OfflineQueueWork.Reanalysis
        let reservation: Value.Reservation
        var allowance: Duration { reservation.visibleAllowance }
        fileprivate init(identity: OfflineQueueWork.Reanalysis, reservation: Value.Reservation) {
            self.identity = identity; self.reservation = reservation
        }
    }

    /// Discovery is read-only. A missing sidecar is not materialized until an
    /// explicit check reserves its budget. An orphaned reservation stays spent.
    static func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                     isCurrent: () -> Bool) throws -> Snapshot {
        try Persistence.transaction(identity, container: container, isCurrent: isCurrent,
            save: { _ in throw Value.Failure.invalid }) { context in
                let (row, _) = try rows(identity, context: context)
                return try snapshot(identity, bytes: row.recoveryPresentationData)
            }
    }

    /// A save that commits and then throws returns no live interval. Reopening
    /// observes the fully charged reservation rather than granting a new clock.
    static func reserve(_ expected: Snapshot, id: UUID = UUID(), container: ModelContainer,
                        isCurrent: () -> Bool,
                        validateOperation: () throws -> Void,
                        canReserveBytes: (Int64) -> Bool = { OfflineQueueStoragePolicy.canAdmitNewPayload(estimatedBytes: $0) },
                        save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Interval {
        // The media-specific owner proves the saved operation before this
        // synchronous, non-suspending transaction. A presentation read alone
        // does not establish that the operation can recover an outcome.
        try validateOperation()
        let reservation = try expected.value.reserve(id: id)
        return try Persistence.transaction(expected.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, job) = try rows(expected.identity, context: context)
            guard try snapshot(expected.identity, bytes: row.recoveryPresentationData) == expected else { throw Value.Failure.stale }
            if expected.bytes == nil {
                guard canReserveBytes(Int64(Value.maximumBytes)) else { throw Value.Failure.invalid }
                // This dedicated reanalysis job previously carries zero bytes.
                // File estimates stay with their existing media owners. Record
                // the full sidecar liability, not just its materialized bytes.
                job.approximateBytes = Int64(Value.maximumBytes)
            }
            row.recoveryPresentationData = try reservation.reserved.encoded()
            // Do not touch job.updatedAt: it belongs to execution snapshot CAS.
            return Interval(identity: expected.identity, reservation: reservation)
        }
    }

    /// Only the live interval can refund unused visible time. A completion or
    /// deletion that removed the child wins; this function never recreates it.
    static func settle(_ interval: Interval, elapsed: Duration, container: ModelContainer,
                       isCurrent: () -> Bool,
                       save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Value {
        try Persistence.transaction(interval.identity, container: container, isCurrent: isCurrent, save: save) { context in
            let (row, _) = try rows(interval.identity, context: context)
            let current = try snapshot(interval.identity, bytes: row.recoveryPresentationData)
            let successor = try interval.reservation.settle(current: current.value, elapsed: elapsed)
            row.recoveryPresentationData = try successor.encoded()
            return successor
        }
    }

    private static func snapshot(_ identity: OfflineQueueWork.Reanalysis, bytes: Data?) throws -> Snapshot {
        let key = Value.Identity(ownerID: identity.ownerID, observationID: identity.observationID, operationID: identity.analysisID)
        let value = try bytes.map { try Value.decode($0, identity: key) } ?? Value.initial(for: key)
        return Snapshot(identity: identity, bytes: bytes, value: value)
    }

    private static func rows(_ identity: OfflineQueueWork.Reanalysis, context: ModelContext) throws -> (OfflineQueuedScan, OfflineJobRecord) {
        let lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
        guard let (row, job) = try Persistence.pair(identity, context: context),
              row.id == lower, row.work == .reanalysis(identity),
              row.mediaAuthorityRaw == "legacy", row.sharedMediaConsumerID == nil,
              job.id == OfflineQueueManager.scanIngestionJobId(scanId: lower), job.subjectId == lower,
              job.kindRaw == OfflineJobKind.observationReanalysisSync.rawValue,
              let status = OfflineJobStatus(rawValue: job.statusRaw), status != .complete, status != .cancelled,
              job.approximateBytes == (row.recoveryPresentationData == nil ? 0 : Int64(Value.maximumBytes)),
              try context.fetch(FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })).isEmpty,
              !(try ObservationHistoryEnrollmentIntent.holds(lower, context: context)),
              try (lower == upper || context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: upper)) == nil) else {
            throw Persistence.IntegrityError.unavailable
        }
        return (row, job)
    }
}
