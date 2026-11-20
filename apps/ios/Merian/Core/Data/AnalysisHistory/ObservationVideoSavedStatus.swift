import Foundation
import SwiftData

/// Bounded advisory facts. An omitted row or a displayed phase never authorizes fresh admission.
@MainActor
struct ObservationVideoSavedStatus {
    enum Phase: Equatable, Sendable {
        case filesPending, prepared, reservationStaged, reservationRunning, reservationUnknown
        case reserved, reservationHeld, reservationUnavailable, reservationConflict
        case uploadPending, uploadRunning, uploadUnknown, uploadReady
        case executionIdle, executionRunning, executionHeld, outcomeRecovery
    }
    struct Summary: Equatable, Sendable {
        let identity: OfflineQueueWork.Reanalysis
        let phase: Phase
    }
    typealias Cursor = ObservationAudioStatusIndex.Cursor
    struct Page: Sendable {
        let items: [Summary]
        let next: Cursor?
        let omittedCount: Int
    }
    typealias Read = @MainActor (OfflineQueueWork.Reanalysis, ModelContainer, @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationVideoResumeStore.Saved
    var read: Read = { try await ObservationVideoResumeStore().read($0, container: $1, isCurrent: $2) }

    func page(ownerID: UUID, observationID: UUID, after cursor: Cursor? = nil, limit: Int = 20,
              container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Page {
        let index = ObservationAudioStatusIndex()
        let links = try index.page(ownerID: ownerID, observationID: observationID, after: cursor,
            limit: limit, route: .video, container: container, isCurrent: isCurrent)
        var items: [Summary] = []
        for (_, work) in links.values {
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            guard case let .reanalysis(identity) = work, identity.ownerID == ownerID, identity.observationID == observationID else { continue }
            do {
                let saved = try await read(identity, container, isCurrent)
                try Task.checkCancellation()
                guard isCurrent() else { throw ObservationHistoryError.accountChanged }
                guard saved.proof.preparation.identity == identity else { throw ObservationHistoryError.resultConflict }
                items.append(.init(identity: identity, phase: try Self.phase(saved.state)))
            } catch {
                guard index.canOmit(error) else { throw error }
            }
        }
        try index.validateParentScope(ownerID: ownerID, observationID: observationID, container: container, isCurrent: isCurrent)
        return Page(items: items, next: links.next, omittedCount: links.values.count - items.count)
    }

    func validateParentScope(ownerID: UUID, observationID: UUID, container: ModelContainer, isCurrent: () -> Bool) throws {
        try ObservationAudioStatusIndex().validateParentScope(ownerID: ownerID, observationID: observationID,
            container: container, isCurrent: isCurrent)
    }

    static func phase(_ state: ObservationVideoResumeStore.State) throws -> Phase {
        switch state {
        case .preparation(.pending): return .filesPending
        case .preparation(.ready): return .prepared
        case let .reservation(saved):
            switch saved.work.phase {
            case .staged: return .reservationStaged
            case .running: return .reservationRunning
            case .unknown: return .reservationUnknown
            case .conflict: return .reservationConflict
            case .observed:
                guard let reply = saved.work.reply else { throw MerianError.invalidResponse }
                switch reply.state {
                case .reserved: return .reserved
                case .held: return .reservationHeld
                case .unavailable: return .reservationUnavailable
                }
            }
        case let .upload(saved):
            if saved.work.receipt?.state == .ready { return .uploadReady }
            switch saved.work.attempts.last?.phase {
            case .running: return .uploadRunning
            case .unknown: return .uploadUnknown
            case .observed, nil: return .uploadPending
            }
        case let .execution(saved):
            if saved.work.consumed { return .outcomeRecovery }
            switch saved.work.phase {
            case .idle: return .executionIdle
            case .running: return .executionRunning
            case .held: return .executionHeld
            }
        }
    }
}
