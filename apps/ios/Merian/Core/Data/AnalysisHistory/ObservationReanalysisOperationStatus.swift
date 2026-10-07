import Foundation
import SwiftData

/// Bounded owner-private status projection. Reading never admits, retries or repairs work.
@MainActor
struct ObservationReanalysisOperationStatus {
    enum Phase: Equatable, Sendable {
        case preparingEvidence, waitingToStart, processing, waitingToRetry, stopping, stopNeedsChecking
        case consentRequired, evidenceUnavailable, reconciliationRequired, retryLimit, executionRetryLimit, terminalFailure
    }
    struct Summary: Identifiable, Equatable, Sendable {
        let id: UUID
        let sourceAnalysisID: UUID
        let phase: Phase
        var retirement: ObservationReanalysisRetirementAction.Affordance?
        var canCheckOutcome = false
    }
    struct Cursor: Equatable, Sendable { fileprivate let childID: String }
    struct Page: Sendable {
        let items: [Summary]
        let next: Cursor?
    }
    var account = ObservationHistoryCloudClient.live

    func page(observationID: UUID, ownerID: UUID, after cursor: Cursor? = nil, limit: Int = 20,
              container: ModelContainer, isCurrent: @escaping () -> Bool) throws -> Page {
        guard (1...20).contains(limit) else { throw ObservationHistoryError.invalidPage }
        let lease = try account.begin(ownerID)
        defer { account.finish(lease) }
        let valid = { isCurrent() && lease.session.userID == ownerID && account.isCurrent(lease) }
        let parent = observationID.uuidString.lowercased(), owner = ownerID.uuidString.lowercased()
        let links: [(String, OfflineQueueWork)] = try ConfirmedSpeciesReviewPersistence.transaction {
            try validateParent(parent, owner: owner, container: container, isCurrent: valid)
            let context = ModelContext(container), after = cursor?.childID ?? "", kind = "reanalysis"
            var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
                $0.workKindRaw == kind && $0.parentObservationID == parent && $0.reanalysisOwnerAccountID == owner && $0.id > after
            }, sortBy: [SortDescriptor(\.id, comparator: .lexical)])
            query.fetchLimit = limit + 1
            query.propertiesToFetch = [\.id, \.workKindRaw, \.parentObservationID, \.sourceAnalysisID, \.reanalysisOwnerAccountID]
            return try context.fetch(query).map { ($0.id, $0.work) }
        }
        var items: [Summary] = []
        for (_, work) in links.prefix(limit) {
            try Task.checkCancellation()
            guard valid() else { throw ObservationHistoryError.accountChanged }
            guard case let .reanalysis(identity) = work, identity.ownerID == ownerID, identity.observationID == observationID else { continue }
            if let phase = try phase(identity, container: container, isCurrent: valid) {
                items.append(.init(id: identity.analysisID, sourceAnalysisID: identity.sourceAnalysisID, phase: phase.phase, retirement: phase.retirement, canCheckOutcome: phase.canCheckOutcome))
            }
        }
        try ConfirmedSpeciesReviewPersistence.transaction {
            try validateParent(parent, owner: owner, container: container, isCurrent: valid)
        }
        // Advance over every inspected linkage, even omitted corruption. Never imply chronology.
        return Page(items: items, next: links.count > limit ? Cursor(childID: links[limit - 1].0) : nil)
    }

    /// Caller owns the read transaction; no nested persistence lock or persistent mutation.
    private func validateParent(_ parent: String, owner: String, container: ModelContainer, isCurrent: () -> Bool) throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let context = ModelContext(container)
        let scan = try ObservationHistorySyncService.enrolledScan(parent, context: context)
        guard scan.analysisOwnerAccountID == owner,
              !(try ObservationHistoryEnrollmentIntent.holds(parent, context: context)) else { throw ObservationHistoryError.unavailable }
    }

    private struct Projection {
        let phase: Phase
        var retirement: ObservationReanalysisRetirementAction.Affordance?
        var canCheckOutcome = false
    }

    private func phase(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer, isCurrent: () -> Bool) throws -> Projection? {
        // Completed results belong to history. A receipt alone can mean discard,
        // so neither receipts nor any result/transport collision imply completion here.
        let exists = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container), lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
            var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
            query.fetchLimit = 1; query.propertiesToFetch = [\.id]
            return try !context.fetch(query).isEmpty
        }
        guard !exists else { return nil }
        if let saved = try? ObservationReanalysisAdmissionStore.read(identity, container: container, isCurrent: isCurrent) {
            if let hold = saved.work.hold {
                switch hold {
                case .consentRequired: return .init(phase: .consentRequired)
                case .evidenceUnavailable: return .init(phase: .evidenceUnavailable)
                case .reconciliationRequired: return .init(phase: .reconciliationRequired)
                case .retryLimit: return .init(phase: .retryLimit)
                }
            }
            if saved.work.state == .waiting { return .init(phase: .waitingToRetry) }
            return .init(phase: saved.work.phase == .filesPending ? .preparingEvidence : .waitingToStart)
        }
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        guard let saved = try? ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: isCurrent) else { return nil }
        let retirement = ObservationReanalysisRetirementAction.affordance(saved)
        if saved.retirement != nil {
            return .init(phase: saved.status == .needsAttention ? .stopNeedsChecking : .stopping, retirement: retirement)
        }
        switch saved.status {
        case .pending: return .init(phase: .waitingToStart)
        case .running: return .init(phase: .processing, retirement: retirement)
        case .waiting: return .init(phase: .waitingToRetry, retirement: retirement)
        case .needsAttention:
            switch saved.hold {
            case .consentRequired: return .init(phase: .consentRequired)
            case .evidenceUnavailable: return .init(phase: .evidenceUnavailable)
            case .terminalFailure: return .init(phase: .terminalFailure)
            case .reconciliationRequired: return .init(phase: .reconciliationRequired, canCheckOutcome: ObservationReanalysisExecutionStore.canRecoverHeldOutcome(saved))
            case .retryLimit: return .init(phase: saved.dispatch == .ready ? .retryLimit : .executionRetryLimit, canCheckOutcome: ObservationReanalysisExecutionStore.canRecoverHeldOutcome(saved))
            case nil: return nil // Held legacy drafts have never been explicitly admitted.
            }
        default: return nil
        }
    }
}

/// Foreground explicit action. The preparation owner retains the account lease; delivery stays in the queue.
@MainActor
struct ObservationReanalysisRetirementAction {
    typealias Store = ObservationReanalysisExecutionStore
    typealias Validator = ObservationReanalysisExecutor.Validator
    enum Affordance: Equatable, Sendable { case requestStop, checkSameStop }
    enum Outcome: Equatable, Sendable { case saved, unavailable }
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient
    let fetch: (ObservationAnalysisExecutionLookup, UUID, @escaping Validator) async throws -> ObservationAnalysisExecutionStatus
    let wake: () -> Void
    var now: () -> Date = Date.init
    var save: (ModelContext) throws -> Void = { try $0.save() }

    static func affordance(_ saved: Store.Snapshot) -> Affordance? {
        guard saved.dispatch != .ready else { return nil }
        if saved.retirement != nil {
            return saved.status == .needsAttention && saved.hold == .reconciliationRequired && saved.server == .admitted
                ? .checkSameStop : nil
        }
        guard saved.status == .waiting || saved.status == .running,
              saved.server == nil || saved.server == .admitted else { return nil }
        return .requestStop
    }

    func perform(_ identity: OfflineQueueWork.Reanalysis, operationID: UUID, container: ModelContainer,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Outcome {
        try await ownership.perform(identity) { owned in
            let lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            let accountCurrent: @MainActor @Sendable () -> Bool = { isCurrent() && lease.session.userID == identity.ownerID && account.isCurrent(lease) }
            let current: @MainActor @Sendable () -> Bool = { accountCurrent() && owned() }
            let expected = try Store.read(identity, container: container, isCurrent: current)
            if expected.retirement != nil {
                if Self.affordance(expected) == .checkSameStop {
                    // Wake discovery even if a save commits and then throws. It never restages or rearms on its own.
                    defer { if accountCurrent() { wake() } }
                    _ = try Store.rearmRetirement(expected, now: now(), container: container, isCurrent: current, save: save)
                    return .saved
                }
                guard expected.status == .waiting || expected.status == .running else { return .unavailable }
                if accountCurrent() { wake() }
                return .saved
            }
            guard Self.affordance(expected) == .requestStop else { return .unavailable }
            let validate: Validator = {
                try Task.checkCancellation()
                guard current(), try Store.read(identity, container: container, isCurrent: current) == expected else {
                    throw ObservationHistoryError.resultConflict
                }
            }
            try validate()
            let status = try await fetch(.init(expected.intent.request), identity.ownerID, validate)
            try validate()
            guard status.state == .admitted else { return .unavailable }
            defer { if accountCurrent() { wake() } }
            _ = try Store.stageRetirement(expected, status: status, operationID: operationID, now: now(),
                container: container, isCurrent: current, save: save)
            return .saved
        }
    }
}

/// Exact outcome lookup only. Unknown work stays held without changing its durable attempt or request.
@MainActor
struct ObservationReanalysisOutcomeAction {
    typealias Store = ObservationReanalysisExecutionStore
    typealias Validator = ObservationReanalysisExecutor.Validator
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient
    let recover: (ObservationReanalysisIntent, @escaping Validator) async throws -> Data?
    let completionAttempted: () -> Void
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func perform(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Bool {
        try await ownership.perform(identity) { owned in
            let lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            let accountCurrent: @MainActor @Sendable () -> Bool = { isCurrent() && lease.session.userID == identity.ownerID && account.isCurrent(lease) }
            let current: @MainActor @Sendable () -> Bool = { accountCurrent() && owned() }
            let expected = try Store.read(identity, container: container, isCurrent: current)
            guard Store.canRecoverHeldOutcome(expected) else { return false }
            let validate: Validator = {
                try Task.checkCancellation()
                guard current(), try Store.read(identity, container: container, isCurrent: current) == expected else {
                    throw ObservationHistoryError.resultConflict
                }
            }
            try validate()
            let bytes = try await recover(expected.intent, validate)
            try validate()
            guard let bytes else { return false }
            // A committed save can throw. Discovery of its cleanup receipt and library
            // refresh are harmless even if the transaction instead rolled back.
            defer { if accountCurrent() { completionAttempted() } }
            _ = try Store.completeHeldOutcome(expected, resultBytes: bytes, container: container, isCurrent: current, save: save)
            return true
        }
    }
}
