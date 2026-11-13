import Foundation
import SwiftData

/// Durable presentation transitions under the existing repository and native
/// account owner. App installation remains separately disabled.
@MainActor
// The full name identifies the exact native operation and its ownership boundary.
// swiftlint:disable:next type_name
struct SharedMediaNativeAppRecoveryPresentationOperations {
    let container: ModelContainer
    let authority: SharedMediaNativeAppOperationAuthority
    let availableBytes: () throws -> Int64
    let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    let configureAudit: (inout SharedMediaNativeScopedAudit) -> Void

    func reserve(_ prepared: SharedMediaNativeReceivingIntent.Prepared, reservationID: UUID) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await Self.reserve(container: container, authority: authority, prepared: prepared, reservationID: reservationID,
            availableBytes: availableBytes, boundary: boundary, audit: {
                _ = try await SharedMediaNativeScopedAudit.runApp(container: container, profile: { authority.profile },
                    header: { try authority.header(container) }, betweenPages: { await Task.yield() }, configure: configureAudit)
            })
    }
    fileprivate func retire(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                            quiet: SharedMediaNativeRecoveryPresentationQuiet) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await Self.reserve(container: container, authority: authority, prepared: prepared, reservationID: nil,
            quiet: quiet, availableBytes: availableBytes, boundary: boundary, audit: audit)
    }
    fileprivate func observed(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> AnalysisRecoveryPresentation? {
        _ = try authority.header(container)
        let context = Self.fresh(container)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: Self.inventory(context, profile: authority.profile))
        let transaction: SharedMediaNativeReceivingIntent.Transaction
        switch witnesses[prepared.package.id] {
        case .initial(let value), .allocating(let value):
            guard try value.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
            transaction = value.transaction
        case .generic(let value):
            guard case .received(let saved, _, let receipt) = value.slot,
                  try saved.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
            transaction = receipt
        default: throw SharedMediaStorageFailure.closed
        }
        let rows = try SharedMediaNativeReceivingRows.readObserved(transaction, in: context)
        guard let bytes = rows.queue.recoveryPresentationData else { return nil }
        return try AnalysisRecoveryPresentation.decode(bytes, identity: .init(ownerID: prepared.profile.ownerID,
            observationID: prepared.observationID, operationID: prepared.operationID))
    }
    func reconcile(_ attempt: SharedMediaNativeRecoveryPresentationAttempt) throws -> Bool {
        try Self.reconcile(attempt, container: container, authority: authority, boundary: boundary)
    }

    func settle(_ original: SharedMediaNativeRecoveryPresentationAttempt, elapsed: Duration) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await advance(original, transition: .settle(elapsed))
    }
    func reserveAgain(_ original: SharedMediaNativeRecoveryPresentationAttempt, reservationID: UUID) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await advance(original, transition: .reserve(reservationID))
    }
    private enum Transition {
        case settle(Duration), reserve(UUID)
        var predecessorKind: SharedMediaNativeRecoveryPresentationAttempt.Kind {
            switch self {
            case .settle: .reservation
            case .reserve: .settlement
            }
        }
        var successorKind: SharedMediaNativeRecoveryPresentationAttempt.Kind {
            switch self {
            case .settle: .settlement
            case .reserve: .reservation
            }
        }
    }
    private func advance(_ original: SharedMediaNativeRecoveryPresentationAttempt, transition: Transition) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try original.requireContinuation(container, authority: authority, kind: transition.predecessorKind)
        let expected = try SharedMediaNativeAppMetadataFacts.successor(original.expected)
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        try await audit()
        try boundary(.beforeSave)
        try await audit()
        try original.requireContinuation(container, authority: authority, kind: transition.predecessorKind)
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = Self.fresh(container), inventory = try Self.inventory(context, profile: authority.profile)
        let proof: SharedMediaNativeRecoveryPresentationPoststate
        switch transition {
        case .settle(let elapsed): proof = try original.proof.settling(elapsed: elapsed, context: context, inventory: inventory)
        case .reserve(let id): proof = try original.proof.reserving(id: id, context: context, inventory: inventory)
        }
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        try SharedMediaNativeReceivingCleanGraph.requirePresentationReplacementRunway(inventoryRevision: inventory.revision,
            packageID: original.prepared.package.id, presentationAdvances: proof.successor.remainingTransitions,
            saveAdvances: 1, witnesses: witnesses, historical: SharedMediaNativeTerminalScan.read(
                container: container, inventoryID: inventory.id))
        // The existing 512-byte charge funds this transition. Never add another
        // first-reservation charge or refund legacy execution/cleanup funding.
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        let previousBytes = try original.presentation.encoded().count, successorBytes = try proof.successor.encoded().count
        // Shorter logical bytes do not guarantee immediate SQLite reclamation.
        // Fund the larger reserved remainder without a second logical charge.
        try budget.totals.checkAvailable(availableBytes(), additionalReservation: Int64(max(0, previousBytes - successorBytes)))
        try proof.requirePredecessor(context, inventory: inventory)
        let rows = try SharedMediaNativeReceivingRows.readPresentation(in: context, proof: proof)
        let result = SharedMediaNativeRecoveryPresentationAttempt(container: container, authority: authority,
            prepared: original.prepared, expected: expected, proof: proof, kind: transition.successorKind)
        do {
            rows.queue.recoveryPresentationData = try proof.successor.encoded()
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try proof.validate(context, inventory: inventory)
            try Task.checkCancellation()
            guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
            let check = Self.fresh(container)
            try proof.requirePredecessor(check, inventory: Self.inventory(check, profile: authority.profile))
            try result.consumeSave()
            try original.consumeContinuation(kind: transition.predecessorKind)
            do { try context.save(); try boundary(.afterSave) } catch { context.rollback() }
            result.acknowledged = (try? Self.reconcile(result, container: container, authority: authority, boundary: boundary)) == true
            return result
        } catch { context.rollback(); throw error }
    }

    private func audit() async throws {
        _ = try await SharedMediaNativeScopedAudit.runApp(container: container, profile: { authority.profile },
            header: { try authority.header(container) }, betweenPages: { await Task.yield() }, configure: configureAudit)
    }

    private static func reserve(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                                prepared: SharedMediaNativeReceivingIntent.Prepared, reservationID: UUID?,
                                quiet: SharedMediaNativeRecoveryPresentationQuiet? = nil, availableBytes: () throws -> Int64,
                                boundary: (SharedMediaNativeMetadataBoundary) throws -> Void,
                                audit: () async throws -> Void) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try quiet?.validate(authority: authority, queueID: prepared.queueID)
        let expected = try authority.header(container)
        guard prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        try await audit()
        // Faults and foreign writes at this boundary precede the final complete
        // audit. A header comparison alone never substitutes for that audit.
        try boundary(.beforeSave)
        try await audit()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = fresh(container), inventory = try inventory(context, profile: authority.profile)
        let proof: SharedMediaNativeRecoveryPresentationPoststate
        if let reservationID {
            guard quiet == nil else { throw SharedMediaStorageFailure.closed }
            proof = try .init(prepared: prepared, reservationID: reservationID, context: context, inventory: inventory)
        } else {
            guard let quiet else { throw SharedMediaStorageFailure.closed }
            try quiet.validate(authority: authority, queueID: prepared.queueID)
            proof = try .forfeiting(prepared: prepared, context: context, inventory: inventory)
        }
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        if quiet == nil { try admit(budget, packageID: prepared.package.id, available: availableBytes()) } else {
            let old = try SharedMediaNativeReceivingRows.readObserved(proof.transaction, in: context).queue.recoveryPresentationData?.count ?? 0
            let new = try proof.successor.encoded().count
            try budget.totals.checkAvailable(availableBytes(), additionalReservation: Int64(max(0, old - new)))
        }
        try proof.requirePredecessor(context, inventory: inventory)
        let rows = try SharedMediaNativeReceivingRows.readPresentation(in: context, proof: proof)
        let attempt = SharedMediaNativeRecoveryPresentationAttempt(container: container, authority: authority,
            prepared: prepared, expected: expected, proof: proof, kind: quiet == nil ? .reservation : .settlement)
        do {
            rows.queue.recoveryPresentationData = try proof.successor.encoded()
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try proof.validate(context, inventory: inventory)
            guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
            let check = fresh(container)
            try proof.requirePredecessor(check, inventory: self.inventory(check, profile: authority.profile))
            // There is one save site and no retry loop. Once attempted, neither
            // the error branch nor readback can invoke it again.
            try quiet?.validate(authority: authority, queueID: prepared.queueID)
            try attempt.consumeSave()
            do { try context.save(); try boundary(.afterSave) } catch { context.rollback() }
            // A failed acknowledgement returns the original opaque attempt for
            // explicit read-only reconciliation, never a replacement reservation.
            attempt.acknowledged = (try? reconcile(attempt, container: container, authority: authority, boundary: boundary)) == true
            return attempt
        } catch { context.rollback(); throw error }
    }

    #if DEBUG
    static func requireFixture(_ container: ModelContainer) throws {
        guard TestExecutionCoordinator.isXCTestRuntimeLoaded,
              container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly else { throw SharedMediaStorageFailure.closed }
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let store = configuration.url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard store.count > temporary.count, store.starts(with: temporary),
              SharedMediaNativeEligibility.fixtureLocation(configuration.url) else { throw SharedMediaStorageFailure.closed }
    }

    #endif

    private static func admit(_ budget: SharedMediaNativeAcquisitionBudget.Snapshot, packageID: UUID,
                              available: Int64) throws {
        let charge = Int64(AnalysisRecoveryPresentation.maximumBytes)
        guard let metadata = budget.metadataByPackage[packageID],
              try SharedMediaStoragePolicy.add(metadata, charge) <= PhotoPreparationPolicy.metadata else {
            throw SharedMediaStorageFailure.capacity
        }
        var totals = budget.totals
        // One additional physical reservation also charges the existing package
        // and durable pool. Legacy receiving funding is neither replaced nor enlarged.
        try totals.include(.init(packageID: packageID, pool: .durable, materialized: 0, reserved: charge))
        try totals.checkAvailable(available)
    }

    private static func reconcile(_ attempt: SharedMediaNativeRecoveryPresentationAttempt, container: ModelContainer,
                                  authority: SharedMediaNativeAppOperationAuthority,
                                  boundary: (SharedMediaNativeMetadataBoundary) throws -> Void) throws -> Bool {
        try attempt.requireBinding(container, authority: authority)
        try boundary(.beforeReadback)
        let after = try SharedMediaNativeAppMetadataFacts.successor(attempt.expected)
        guard try authority.header(container) == after else { throw SharedMediaStorageFailure.stale }
        let context = fresh(container)
        try attempt.proof.requirePersisted(context, inventory: inventory(context, profile: authority.profile))
        guard try authority.header(container) == after else { throw SharedMediaStorageFailure.stale }
        return true
    }

    private static func fresh(_ container: ModelContainer) -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
    private static func inventory(_ context: ModelContext, profile: SharedMediaNativeAppProfile) throws -> SharedMediaInventoryRecord {
        let id = profile.inventoryID
        return try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
}

/// Ephemeral identity for a single attempted save. It holds no lease, lock,
/// repository, clock or executable reservation. Cold bytes cannot construct it.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
final class SharedMediaNativeRecoveryPresentationAttempt {
    fileprivate enum Kind { case reservation, settlement }
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    fileprivate let expected: SharedMediaNativeAppEligibility.Header
    fileprivate let proof: SharedMediaNativeRecoveryPresentationPoststate
    private let containerID: ObjectIdentifier, writerEpoch: UUID
    private var saveConsumed = false
    fileprivate let kind: Kind
    private var continuationConsumed = false
    fileprivate(set) var acknowledged = false
    var presentation: AnalysisRecoveryPresentation { proof.successor }
    var visibleAllowance: Duration? {
        acknowledged && kind == .reservation && !continuationConsumed ? proof.visibleAllowance : nil
    }

    fileprivate init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                     prepared: SharedMediaNativeReceivingIntent.Prepared,
                     expected: SharedMediaNativeAppEligibility.Header,
                     proof: SharedMediaNativeRecoveryPresentationPoststate, kind: Kind = .reservation) {
        containerID = ObjectIdentifier(container); writerEpoch = authority.writerEpoch
        self.prepared = prepared; self.expected = expected; self.proof = proof
        self.kind = kind
    }
    fileprivate func consumeSave() throws {
        guard !saveConsumed else { throw SharedMediaStorageFailure.closed }; saveConsumed = true
    }
    fileprivate func requireContinuation(_ container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority, kind expectedKind: Kind) throws {
        try requireBinding(container, authority: authority)
        guard kind == expectedKind, acknowledged, !continuationConsumed else { throw SharedMediaStorageFailure.closed }
    }
    fileprivate func consumeContinuation(kind expectedKind: Kind) throws {
        guard kind == expectedKind, acknowledged, !continuationConsumed else { throw SharedMediaStorageFailure.closed }
        continuationConsumed = true
    }
    fileprivate func requireBinding(_ container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority) throws {
        guard saveConsumed, containerID == ObjectIdentifier(container), writerEpoch == authority.writerEpoch,
              prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
    }
}

@MainActor
extension SharedMediaNativeOriginalOwner {
    #if DEBUG
    func reserveAppRecoveryPresentationForTesting(_ candidate: SharedMediaNativeReceivedCandidate) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await executeAppRecovery(.init(owner: self, kind: .fixtureCandidate(candidate))).attempt()
    }
    func reserveAppRecoveryPresentationForTesting(_ prepared: SharedMediaNativeReceivingIntent.Prepared, reservationID: UUID) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await executeAppRecovery(.init(owner: self, kind: .fixtureReserve(prepared, reservationID))).attempt()
    }
    func reserveAgainAppRecoveryPresentationForTesting(_ attempt: SharedMediaNativeRecoveryPresentationAttempt) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await executeAppRecovery(.init(owner: self, kind: .fixtureAgain(attempt, UUID()))).attempt()
    }
    func settleAppRecoveryPresentationForTesting(_ attempt: SharedMediaNativeRecoveryPresentationAttempt, elapsed: Duration) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try await executeAppRecovery(.init(owner: self, kind: .fixtureSettle(attempt, elapsed))).attempt()
    }
    func reconcileAppRecoveryPresentationForTesting(_ attempt: SharedMediaNativeRecoveryPresentationAttempt) async throws -> Bool {
        guard case .reconciled(let result) = try await executeAppRecovery(.init(owner: self, kind: .fixtureReconcile(attempt))) else { throw SharedMediaStorageFailure.closed }
        return result
    }
    #endif
}

/// The existing owner retains this registry for its entire writer epoch. Only
/// this file can publish or quiesce an interval; factory-local absence is not proof.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
final class SharedMediaNativeRecoveryPresentationRegistry {
    fileprivate let writerEpoch: UUID
    fileprivate var live: [UUID: UUID] = [:]
    fileprivate var attempts: [UUID: SharedMediaNativeRecoveryPresentationAttempt] = [:]
    var hasLiveIntervals: Bool { !live.isEmpty }
    var identity: UUID { writerEpoch }
    #if DEBUG
    var retainedAttemptCountForTesting: Int { attempts.count }
    #endif
    init(writerEpoch: UUID) { self.writerEpoch = writerEpoch }
}

@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
private struct SharedMediaNativeRecoveryPresentationQuiet {
    let registry: SharedMediaNativeRecoveryPresentationRegistry
    func validate(authority: SharedMediaNativeAppOperationAuthority, queueID: UUID) throws {
        guard registry.writerEpoch == authority.writerEpoch, registry.live[queueID] == nil else {
            throw SharedMediaStorageFailure.closed
        }
    }
}

/// One-way clock capability. The model freezes visible time before consuming
/// settlement. Failure cannot revive this interval or quiesce a newer one.
@MainActor
// The full domain name distinguishes this state or capability from adjacent storage boundaries.
// swiftlint:disable:next type_name
final class SharedMediaNativeRecoveryPresentationInterval {
    let allowance: Duration
    private let owner: SharedMediaNativeOriginalOwner
    private let registry: SharedMediaNativeRecoveryPresentationRegistry
    private let attempt: SharedMediaNativeRecoveryPresentationAttempt
    private let identity = UUID()
    private var consumed = false
    fileprivate init(owner: SharedMediaNativeOriginalOwner, registry: SharedMediaNativeRecoveryPresentationRegistry,
                     attempt: SharedMediaNativeRecoveryPresentationAttempt, allowance: Duration) throws {
        guard registry.live[attempt.prepared.queueID] == nil else { throw SharedMediaStorageFailure.closed }
        self.owner = owner; self.registry = registry; self.attempt = attempt; self.allowance = allowance
        registry.live[attempt.prepared.queueID] = identity
    }
    private func quiesce() throws {
        guard !consumed, registry.live[attempt.prepared.queueID] == identity else { throw SharedMediaStorageFailure.closed }
        consumed = true; registry.live[attempt.prepared.queueID] = nil
    }
    fileprivate func abandonUndelivered() { try? quiesce() }
    func settle(elapsed: Duration) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try quiesce()
        return try await owner.executeAppRecovery(.init(owner: owner, kind: .settle(self, elapsed))).attempt()
    }
    fileprivate var prepared: SharedMediaNativeReceivingIntent.Prepared { attempt.prepared }
    fileprivate func persistSettlement(_ operation: SharedMediaNativeAppRecoveryPresentationOperations, elapsed: Duration) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        guard consumed else { throw SharedMediaStorageFailure.closed }
        let result = try await operation.settle(attempt, elapsed: elapsed)
        registry.attempts[attempt.prepared.queueID] = result
        return result
    }
}

@MainActor
extension SharedMediaNativeOriginalOwner {
    func applyAppInitialResult(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                               readOriginal: @escaping @MainActor (InitialCompletionDocuments.CpmAdmission, @escaping @MainActor @Sendable () throws -> Void) async throws -> InitialCompletionDocuments.CpmAcquisition?) async throws -> SharedMediaNativeConsumerCohort.AppliedInitial? {
        let registry = recoveryPresentationLive, previous = recoveryPresentationLive.attempts[prepared.queueID]
        guard let verified = try await verifiedAppInitialApplication(prepared, readOriginal: readOriginal) else { return nil }
        try verified.require(self, prepared: prepared)
        let applied = verified.cohort
        // Retire only after the verified application/replay and every outer
        // account/lock fence returns. Lost replies retain the exact attempt.
        // The identity captured before awaiting cannot remove a newer entry.
        if let previous, registry.attempts[prepared.queueID] === previous,
           registry.live[prepared.queueID] == nil {
            do {
                guard try previous.prepared.encoded() == prepared.encoded(),
                      applied.original == previous.proof.transaction.cohort else { return applied }
                _ = try applied.encoded()
                try applied.receipt.requirePresentation(previous.presentation.encoded())
                registry.attempts[prepared.queueID] = nil
            } catch { /* Keep uncertainty; bookkeeping cannot undo a verified result. */ }
        }
        return applied
    }

    func prepareAppRecoveryInterval(_ candidate: SharedMediaNativeReceivedCandidate) async throws -> SharedMediaNativeRecoveryPresentationInterval? {
        let action = SharedMediaNativeRecoveryAction(owner: self, kind: .prepare(candidate))
        do {
            guard case .interval(let value) = try await executeAppRecovery(action) else { throw SharedMediaStorageFailure.closed }
            return value
        } catch { action.abandonUndelivered(); throw error }
    }
    fileprivate func prepareRecoveryInterval(_ operation: SharedMediaNativeAppRecoveryPresentationOperations,
                                             prepared: SharedMediaNativeReceivingIntent.Prepared) async throws -> SharedMediaNativeRecoveryPresentationInterval? {
        let quiet = SharedMediaNativeRecoveryPresentationQuiet(registry: self.recoveryPresentationLive)
        try quiet.validate(authority: operation.authority, queueID: prepared.queueID)
        // Existing owner dispatch serializes this check through every
        // await/save below. Never evict uncertain entries to admit more.
        // Capacity holds only the clock; explicit status remains usable.
        guard self.recoveryPresentationLive.attempts[prepared.queueID] != nil ||
            self.recoveryPresentationLive.attempts.count < PhotoPreparationPolicy.maximumPackages else { return nil }
        let attempt: SharedMediaNativeRecoveryPresentationAttempt
        if let previous = self.recoveryPresentationLive.attempts[prepared.queueID] {
            guard try previous.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
            if !previous.acknowledged || previous.kind == .reservation {
                // Reconciliation never upgrades the old acknowledgement or
                // reconstructs a clock. An absent/changed successor stays held.
                guard (try? operation.reconcile(previous)) == true else { return nil }
                if previous.presentation.activeReservationID != nil {
                    let retired = try await operation.retire(prepared, quiet: quiet)
                    self.recoveryPresentationLive.attempts[prepared.queueID] = retired
                }
                return nil
            }
            guard !previous.presentation.needsAttention else { return nil }
            attempt = try await operation.reserveAgain(previous, reservationID: UUID())
        } else if let saved = try operation.observed(prepared) {
            if saved.activeReservationID != nil {
                let retired = try await operation.retire(prepared, quiet: quiet)
                self.recoveryPresentationLive.attempts[prepared.queueID] = retired
            }
            // Cold bytes never reconstruct a live reservation or allowance.
            return nil
        } else { attempt = try await operation.reserve(prepared, reservationID: UUID()) }
        // Retain before final query, lock release or account checks can
        // throw. Never retry a consumed predecessor after uncertainty.
        self.recoveryPresentationLive.attempts[prepared.queueID] = attempt
        guard let allowance = attempt.visibleAllowance else { return nil }
        let interval = try SharedMediaNativeRecoveryPresentationInterval(owner: self,
            registry: self.recoveryPresentationLive, attempt: attempt, allowance: allowance)
        return interval
    }
}

/// Closed one-use action for the existing owner. No caller can supply a lock,
/// arbitrary operation callback, or a second target distinct from execution.
@MainActor
final class SharedMediaNativeRecoveryAction {
    fileprivate enum Kind {
        case prepare(SharedMediaNativeReceivedCandidate), settle(SharedMediaNativeRecoveryPresentationInterval, Duration)
        #if DEBUG
        case fixtureCandidate(SharedMediaNativeReceivedCandidate), fixtureReserve(SharedMediaNativeReceivingIntent.Prepared, UUID)
        case fixtureAgain(SharedMediaNativeRecoveryPresentationAttempt, UUID), fixtureSettle(SharedMediaNativeRecoveryPresentationAttempt, Duration)
        case fixtureReconcile(SharedMediaNativeRecoveryPresentationAttempt)
        #endif
    }
    enum Result: Sendable {
        case interval(SharedMediaNativeRecoveryPresentationInterval?), attempted(SharedMediaNativeRecoveryPresentationAttempt), reconciled(Bool)
        func attempt() throws -> SharedMediaNativeRecoveryPresentationAttempt {
            guard case .attempted(let value) = self else { throw SharedMediaStorageFailure.closed }; return value
        }
    }
    private let owner: SharedMediaNativeOriginalOwner, kind: Kind
    private var claimed = false, performed = false
    private var selected: SharedMediaNativeReceivingIntent.Prepared?
    private var published: SharedMediaNativeRecoveryPresentationInterval?
    fileprivate init(owner: SharedMediaNativeOriginalOwner, kind: Kind) { self.owner = owner; self.kind = kind }
    func claim(_ owner: SharedMediaNativeOriginalOwner) throws {
        guard self.owner === owner, !claimed else { throw SharedMediaStorageFailure.closed }; claimed = true
    }
    private var candidate: SharedMediaNativeReceivedCandidate? {
        switch kind {
        case .prepare(let value): return value
        #if DEBUG
        case .fixtureCandidate(let value): return value
        #endif
        default: return nil
        }
    }
    var needsCandidateRead: Bool { candidate != nil }
    func target(storage: SharedMediaNativeStorageRepository, grant: SharedMediaNativeAppDispatchGrant) async throws -> SharedMediaNativeReceivingIntent.Prepared {
        guard claimed, selected == nil, !performed, let candidate else { throw SharedMediaStorageFailure.closed }
        let prepared = try await storage.appReceivingRead(grant: grant, query: SharedMediaNativeReceivingQuery.received(candidate)).prepared
        selected = prepared; return prepared
    }
    func selectFixedTarget() throws -> SharedMediaNativeReceivingIntent.Prepared {
        guard claimed, selected == nil, !performed, candidate == nil else { throw SharedMediaStorageFailure.closed }
        let prepared: SharedMediaNativeReceivingIntent.Prepared
        switch kind {
        case .settle(let interval, _): prepared = interval.prepared
        #if DEBUG
        case .fixtureReserve(let value, _): prepared = value
        case .fixtureAgain(let value, _), .fixtureSettle(let value, _), .fixtureReconcile(let value): prepared = value.prepared
        #endif
        default: throw SharedMediaStorageFailure.closed
        }
        selected = prepared; return prepared
    }
    func validateTarget(_ prepared: SharedMediaNativeReceivingIntent.Prepared, storage: SharedMediaNativeStorageRepository, grant: SharedMediaNativeAppDispatchGrant) throws {
        try grant.validate()
        guard claimed, prepared.profile == grant.profile, let selected, try selected.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
        if let candidate {
            let current = try storage.requireAppReceivingRead(grant: grant, query: SharedMediaNativeReceivingQuery.received(candidate))
            guard try current.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
        }
    }
    func perform(_ operation: SharedMediaNativeAppRecoveryPresentationOperations, prepared: SharedMediaNativeReceivingIntent.Prepared) async throws -> Result {
        guard claimed, !performed, let selected, try selected.encoded() == prepared.encoded(),
              prepared.profile == operation.authority.profile else { throw SharedMediaStorageFailure.closed }
        performed = true
        switch kind {
        case .prepare:
            let value = try await owner.prepareRecoveryInterval(operation, prepared: prepared)
            published = value; return .interval(value)
        case .settle(let interval, let elapsed): return .attempted(try await interval.persistSettlement(operation, elapsed: elapsed))
        #if DEBUG
        case .fixtureCandidate:
            try SharedMediaNativeAppRecoveryPresentationOperations.requireFixture(operation.container)
            return .attempted(try await operation.reserve(prepared, reservationID: UUID()))
        case .fixtureReserve(_, let id):
            try SharedMediaNativeAppRecoveryPresentationOperations.requireFixture(operation.container)
            return .attempted(try await operation.reserve(prepared, reservationID: id))
        case .fixtureAgain(let attempt, let id):
            try SharedMediaNativeAppRecoveryPresentationOperations.requireFixture(operation.container)
            return .attempted(try await operation.reserveAgain(attempt, reservationID: id))
        case .fixtureSettle(let attempt, let elapsed):
            try SharedMediaNativeAppRecoveryPresentationOperations.requireFixture(operation.container)
            return .attempted(try await operation.settle(attempt, elapsed: elapsed))
        case .fixtureReconcile(let attempt):
            try SharedMediaNativeAppRecoveryPresentationOperations.requireFixture(operation.container)
            return .reconciled(try operation.reconcile(attempt))
        #endif
        }
    }
    fileprivate func abandonUndelivered() { published?.abandonUndelivered() }
}
