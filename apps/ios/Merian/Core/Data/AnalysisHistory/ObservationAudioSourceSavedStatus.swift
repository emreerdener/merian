import Foundation
import SwiftData

/// Advisory local facts only. Reading never creates an execution capability or proves safe new admission.
@MainActor
struct ObservationAudioSourceSavedStatus {
    enum Phase: Equatable, Sendable { case staged, checking, unknown, reserved, held, unavailable, conflict }
    struct Summary: Equatable, Sendable {
        let identity: OfflineQueueWork.Reanalysis
        let phase: Phase
    }
    typealias Cursor = ObservationAudioStatusIndex.Cursor
    struct Page: Sendable {
        let items: [Summary]
        let next: Cursor?
        /// Includes unsupported/photo/held drafts and invalid links; never interpret omissions as absence.
        let omittedCount: Int
    }
    typealias Read = @MainActor (OfflineQueueWork.Reanalysis, ModelContainer, @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioSourceResumeStore.Saved
    var read: Read = { try await ObservationAudioSourceResumeStore().read($0, container: $1, isCurrent: $2) }

    /// Caller supplies current common owner/generation/container scope; this local reader acquires no account lease.
    func page(ownerID: UUID, observationID: UUID, after cursor: Cursor? = nil, limit: Int = 20,
              container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Page {
        let index = ObservationAudioStatusIndex()
        let links = try index.page(ownerID: ownerID, observationID: observationID, after: cursor,
            limit: limit, route: .source, container: container, isCurrent: isCurrent)
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
                items.append(.init(identity: identity, phase: try phase(saved.snapshot.work)))
            } catch {
                // Only classified immutable validation failures are omissions. Store/I/O/account failures propagate.
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

    private func phase(_ work: ObservationSourceReservationWork) throws -> Phase {
        switch work.state {
        case .staged: return .staged
        case .running: return .checking
        case .unknown: return .unknown
        case .conflict: return .conflict
        case .observed:
            guard let reply = work.reply else { throw MerianError.invalidResponse }
            switch reply.state {
            case .reserved: return .reserved
            case .held: return .held
            case .unavailable: return .unavailable
            }
        }
    }
}
