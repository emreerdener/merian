import Foundation
import SwiftData

/// First durable reservation and one-way settlement through the real native
/// owner, restricted to DEBUG qualification in disposable test databases.
/// Production writing, visible clocks and positive cleanup remain closed.
@MainActor
struct SharedMediaNativeAppRecoveryPresentationOperations {
    #if DEBUG
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
            switch self { case .settle: .reservation; case .reserve: .settlement }
        }
        var successorKind: SharedMediaNativeRecoveryPresentationAttempt.Kind {
            switch self { case .settle: .settlement; case .reserve: .reservation }
        }
    }
    private func advance(_ original: SharedMediaNativeRecoveryPresentationAttempt, transition: Transition) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try Self.requireFixture(container)
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
            saveAdvances: 1, witnesses: witnesses, terminalConsumptionAdvances: SharedMediaNativeTerminalScan.read(
                container: container, inventoryID: inventory.id).consumptionAdvances)
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
            do { try context.save(); try boundary(.afterSave) }
            catch { context.rollback() }
            result.acknowledged = (try? Self.reconcile(result, container: container, authority: authority, boundary: boundary)) == true
            return result
        } catch { context.rollback(); throw error }
    }

    private func audit() async throws {
        _ = try await SharedMediaNativeScopedAudit.runApp(container: container, profile: { authority.profile },
            header: { try authority.header(container) }, betweenPages: { await Task.yield() }, configure: configureAudit)
    }

    private static func reserve(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        prepared: SharedMediaNativeReceivingIntent.Prepared, reservationID: UUID,
                        availableBytes: () throws -> Int64,
                        boundary: (SharedMediaNativeMetadataBoundary) throws -> Void,
                        audit: () async throws -> Void) async throws -> SharedMediaNativeRecoveryPresentationAttempt {
        try requireFixture(container)
        let expected = try authority.header(container)
        guard prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        try await audit()
        // Faults and foreign writes at this boundary precede the final complete
        // audit. A header comparison alone never substitutes for that audit.
        try boundary(.beforeSave)
        try await audit()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        let context = fresh(container), inventory = try inventory(context, profile: authority.profile)
        let proof = try SharedMediaNativeRecoveryPresentationPoststate(prepared: prepared, reservationID: reservationID,
            context: context, inventory: inventory)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        try admit(budget, packageID: prepared.package.id, available: availableBytes())
        try proof.requirePredecessor(context, inventory: inventory)
        let rows = try SharedMediaNativeReceivingRows.readPresentation(in: context, proof: proof)
        let attempt = SharedMediaNativeRecoveryPresentationAttempt(container: container, authority: authority,
            prepared: prepared, expected: expected, proof: proof)
        do {
            rows.queue.recoveryPresentationData = try proof.successor.encoded()
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try proof.validate(context, inventory: inventory)
            guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
            let check = fresh(container)
            try proof.requirePredecessor(check, inventory: self.inventory(check, profile: authority.profile))
            // There is one save site and no retry loop. Once attempted, neither
            // the error branch nor readback can invoke it again.
            try attempt.consumeSave()
            do { try context.save(); try boundary(.afterSave) }
            catch { context.rollback() }
            // A failed acknowledgement returns the original opaque attempt for
            // explicit read-only reconciliation, never a replacement reservation.
            attempt.acknowledged = (try? reconcile(attempt, container: container, authority: authority, boundary: boundary)) == true
            return attempt
        } catch { context.rollback(); throw error }
    }

    static func requireFixture(_ container: ModelContainer) throws {
        guard NSClassFromString("XCTestCase") != nil,
              container.configurations.count == 1, let configuration = container.configurations.first,
              !configuration.isStoredInMemoryOnly else { throw SharedMediaStorageFailure.closed }
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let store = configuration.url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard store.count > temporary.count, store.starts(with: temporary),
              SharedMediaNativeEligibility.fixtureLocation(configuration.url) else { throw SharedMediaStorageFailure.closed }
    }

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
        try requireFixture(container)
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
    #endif
}

#if DEBUG
/// Ephemeral identity for a single attempted save. It holds no lease, lock,
/// repository, clock or executable reservation. Cold bytes cannot construct it.
@MainActor
final class SharedMediaNativeRecoveryPresentationAttempt {
    fileprivate enum Kind { case reservation, settlement }
    let prepared: SharedMediaNativeReceivingIntent.Prepared
    fileprivate let expected: SharedMediaNativeAppEligibility.Header
    fileprivate let proof: SharedMediaNativeRecoveryPresentationPoststate
    private let containerID: ObjectIdentifier, writerEpoch: UUID
    private var saveConsumed = false
    private let kind: Kind
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
#endif
