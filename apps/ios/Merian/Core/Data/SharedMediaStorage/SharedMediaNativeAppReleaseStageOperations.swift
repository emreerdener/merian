import Foundation
import SwiftData

/// Dedicated inactive two-row writer. It consumes no media, AI dispatch, scan
/// token or fresh free-space reservation. Existing generic receiving stays closed.
@MainActor
// The full name identifies the exact native operation and its ownership boundary.
// swiftlint:disable:next type_name
final class SharedMediaNativeAppReleaseStageOperations {
    typealias Request = SharedMediaNativeReleaseStartRequest
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Reader = SharedMediaNativeReceivedReleaseSnapshot
    enum Saved: Equatable, Sendable {
        case staged(Request)
        case releasing(Values.Progress)
    }
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let expected: SharedMediaNativeAppEligibility.Header
    private let settlement: SharedMediaNativeReleaseStageSettlement
    private let recoveryHeader: () throws -> SharedMediaNativeAppEligibility.Header
    private let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    private let io: SharedMediaNativeOriginalIO
    private let fileBinding: SharedMediaNativeBinding
    private let verifyInspection: (SharedMediaNativePairInspection) throws -> Void
    private let verifyRetiring: (SharedMediaNativeRetiringPairInspection) throws -> Void
    private let verifyAbsence: (SharedMediaNativePairAbsence) throws -> Void
    private let verifyOriginal: (SharedMediaNativeHeldOriginalInspection) throws -> SharedMediaNativeHeldOriginalInspection
    private let requireOriginalAbsence: (SharedMediaNativeRetirementState) throws -> Void
    private let verifyPrefix: (SharedMediaNativeReleasePrefix) throws -> Void
    private var consumed = false

    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 expected: SharedMediaNativeAppEligibility.Header, settlement: SharedMediaNativeReleaseStageSettlement,
                 io: SharedMediaNativeOriginalIO, fileBinding: SharedMediaNativeBinding,
                 verifyInspection: @escaping (SharedMediaNativePairInspection) throws -> Void, verifyAbsence: @escaping (SharedMediaNativePairAbsence) throws -> Void, verifyRetiring: @escaping (SharedMediaNativeRetiringPairInspection) throws -> Void,
                 verifyOriginal: @escaping (SharedMediaNativeHeldOriginalInspection) throws -> SharedMediaNativeHeldOriginalInspection,
                 requireOriginalAbsence: @escaping (SharedMediaNativeRetirementState) throws -> Void,
                 verifyPrefix: @escaping (SharedMediaNativeReleasePrefix) throws -> Void,
                 recoveryHeader: @escaping () throws -> SharedMediaNativeAppEligibility.Header,
                 boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) {
        self.container = container; self.authority = authority; self.expected = expected
        self.io = io; self.fileBinding = fileBinding; self.verifyInspection = verifyInspection; self.verifyAbsence = verifyAbsence; self.verifyRetiring = verifyRetiring
        self.settlement = settlement; self.boundary = boundary; self.recoveryHeader = recoveryHeader
        self.verifyOriginal = verifyOriginal; self.requireOriginalAbsence = requireOriginalAbsence
        self.verifyPrefix = verifyPrefix
    }
    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        settlement: SharedMediaNativeReleaseStageSettlement,
                        io: SharedMediaNativeOriginalIO, fileBinding: SharedMediaNativeBinding,
                        verifyInspection: @escaping (SharedMediaNativePairInspection) throws -> Void, verifyAbsence: @escaping (SharedMediaNativePairAbsence) throws -> Void, verifyRetiring: @escaping (SharedMediaNativeRetiringPairInspection) throws -> Void,
                        verifyOriginal: @escaping (SharedMediaNativeHeldOriginalInspection) throws -> SharedMediaNativeHeldOriginalInspection,
                        requireOriginalAbsence: @escaping (SharedMediaNativeRetirementState) throws -> Void,
                        verifyPrefix: @escaping (SharedMediaNativeReleasePrefix) throws -> Void,
                        recoveryHeader: @escaping () throws -> SharedMediaNativeAppEligibility.Header,
                        boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) async throws -> SharedMediaNativeAppReleaseStageOperations {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        return .init(container: container, authority: authority, expected: expected, settlement: settlement, io: io, fileBinding: fileBinding,
            verifyInspection: verifyInspection, verifyAbsence: verifyAbsence, verifyRetiring: verifyRetiring, verifyOriginal: verifyOriginal, requireOriginalAbsence: requireOriginalAbsence, verifyPrefix: verifyPrefix, recoveryHeader: recoveryHeader, boundary: boundary)
    }

    private func discover(packageID: UUID) throws -> Saved? {
        try validate()
        let c = fresh(), inventory = try inventory(c)
        guard let witness = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)[packageID] else { return nil }
        switch witness {
        case .initial, .allocating: throw SharedMediaStorageFailure.closed
        case .generic(let value):
            guard value.recoveryPresentationData == nil else { throw SharedMediaStorageFailure.closed }
            return nil
        case .staged(let value): return .staged(value.origin.request)
        case .releasing(let value): return .releasing(value.release.progress)
        }
    }

    func discover(prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Saved? {
        guard prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        let saved = try discover(packageID: prepared.package.id)
        switch saved {
        case .staged(let request):
            guard request.preparedSHA256 == SharedMediaAcquisitionEncoding.digest(try prepared.encoded()),
                  request.queueID == prepared.queueID, request.observationID == prepared.observationID else { throw SharedMediaStorageFailure.closed }
        case .releasing(let progress):
            let c = fresh(), inventory = try inventory(c)
            guard case .releasing(let witness) = try SharedMediaNativeReceivingCleanGraph.pending(c, inventory: inventory)[prepared.package.id],
                  try witness.release.origin.prepared.encoded() == prepared.encoded(), witness.release.progress == progress else { throw SharedMediaStorageFailure.closed }
        case nil: break
        }
        try validate(); return saved
    }

    /// The caller fixes its releaseID before mutation locks. Discovery never
    /// invents a replacement for a saved sidecar or consumed Progress identity.
    func request(packageID: UUID, releaseID: UUID) throws -> SharedMediaNativeReleaseStageAdmission {
        try validate()
        guard settlement.request == nil, try discover(packageID: packageID) == nil else { throw SharedMediaStorageFailure.closed }
        let snapshot = try Reader.read(packageID: packageID, inventoryID: authority.profile.inventoryID,
            releaseID: releaseID, context: fresh(), checkpoint: validate)
        guard snapshot.components.recoveryPresentationData == nil else { throw SharedMediaStorageFailure.closed }
        let request = try Request(prepared: snapshot.components.prepared, received: snapshot.components.received,
            stagePreHeader: expected, releaseID: releaseID)
        return try settlement.issue(request, row: snapshot.slot)
    }

    /// Descriptive persisted requests can only recover their original outcome.
    func reconcile(_ request: Request) throws -> Saved {
        try request.validate(); try validate()
        guard request.profile == authority.profile,
              settlement.request == nil || settlement.request == request else { throw SharedMediaStorageFailure.closed }
        return try recover(request, exactSuccessor: false)
    }

    func start(_ request: Request) async throws -> Values.Progress {
        try await SharedMediaNativeAppReleaseStartOperations(container: container, authority: authority,
            expected: expected, settlement: settlement, recoveryHeader: recoveryHeader, boundary: boundary).apply(request)
    }

    #if DEBUG
    /// Read-only fixture observation. The attempt contains no settlement grant.
    func frozenPairForTesting(_ progress: Values.Progress) throws -> SharedMediaNativeReleasePairAttempt? {
        try validate()
        return try settlement.frozenPair(settlement.pairAdmission(progress))
    }
    #endif
    func continueRelease(_ progress: Values.Progress) async throws {
        try await SharedMediaNativeAppReleaseContinuationOperations(container: container, authority: authority,
            expected: expected, settlement: settlement, io: io, binding: fileBinding, verify: verifyPrefix).apply(progress)
    }
    func retirePair(_ progress: Values.Progress) async throws -> Values.Progress {
        try await SharedMediaNativeAppReleasePairOperations(container: container, authority: authority,
            expected: expected, settlement: settlement, io: io, binding: fileBinding, verify: verifyInspection, verifyPrefix: verifyPrefix,
            recoveryHeader: recoveryHeader, boundary: boundary).apply(progress)
    }
    func removePair(_ progress: Values.Progress) async throws -> Values.Progress {
        try await SharedMediaNativeAppReleasePairRemovalOperations(container: container, authority: authority,
            expected: expected, settlement: settlement, io: io, binding: fileBinding, verify: verifyRetiring,
            verifyAbsence: verifyAbsence, recoveryHeader: recoveryHeader, boundary: boundary).apply(progress)
    }
    func disposeOriginal(_ progress: Values.Progress) async throws -> Values.Progress {
        try await SharedMediaNativeAppOriginalDispositionOperations(container: container, authority: authority,
            expected: expected, settlement: settlement, recoveryHeader: recoveryHeader, boundary: boundary).apply(progress)
    }
    func removeOriginal(_ progress: Values.Progress) async throws -> Values.Progress {
        try await SharedMediaNativeAppOriginalRemovalOperations(container: container, authority: authority,
            expected: expected, settlement: settlement, io: io, binding: fileBinding,
            verify: verifyOriginal, requireAbsence: requireOriginalAbsence,
            recoveryHeader: recoveryHeader, boundary: boundary).apply(progress)
    }
    func finishRelease(_ progress: Values.Progress) async throws -> Values.Released {
        try await SharedMediaNativeAppReceivingTerminalOperations(container: container, authority: authority,
            expected: expected, settlement: settlement, io: io, binding: fileBinding, verify: verifyPrefix,
            recoveryHeader: recoveryHeader, boundary: boundary).apply(progress)
    }
    func reconcilePair(_ progress: Values.Progress) throws -> Values.Progress {
        try progress.validate(); try validate()
        if settlement.pairAttempt != nil { return try settlement.recoverPair(progress) }
        guard progress.plan.profile == authority.profile,
              settlement.request == nil || settlement.pairAttempt?.after == progress else { throw SharedMediaStorageFailure.closed }
        let value = try SharedMediaNativeReleasePairRecovery.read(progress, container: container,
            closure: settlement.pairAttempt?.closure, header: { try self.authority.header(self.container) })
        if settlement.pairAttempt != nil { try settlement.resolvedPair(value) }
        return value
    }

    func reconcileStart(_ progress: Values.Progress) throws -> Values.Progress {
        try progress.validate(); try validate()
        guard progress.plan.profile == authority.profile,
              settlement.request == nil || settlement.startProgress == progress else { throw SharedMediaStorageFailure.closed }
        let value = try SharedMediaNativeReleaseStartRecovery.read(progress, container: container,
            header: { try self.authority.header(self.container) })
        if settlement.startProgress != nil { try settlement.resolvedStart(value) }
        return value
    }

    func apply(_ admission: SharedMediaNativeReleaseStageAdmission) async throws -> Saved {
        let request = admission.request
        try request.validate(); try validate()
        guard request.profile == authority.profile, !consumed else { throw SharedMediaStorageFailure.closed }
        consumed = true
        try settlement.validate(admission)
        guard request.stagePreHeader == expected else { throw SharedMediaStorageFailure.stale }
        try await SharedMediaNativeReleaseStageIdentity.audit(request.releaseID, container: container, check: validate)
        let context = fresh(), inventory = try inventory(context)
        let snapshot = try predecessor(request, context: context, inventory: inventory)
        try settlement.validate(admission, row: snapshot.predecessor.slot)
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(request.packageID, in: context) else { throw SharedMediaStorageFailure.stale }
        let seal = try SharedMediaNativeReleaseStagePoststate(request: request, snapshot: snapshot,
            context: context, row: row, inventory: inventory)
        do {
            row.releaseStartData = try request.encoded()
            row.releaseStartSHA256 = SharedMediaAcquisitionEncoding.digest(row.releaseStartData!)
            inventory.revision = try request.postStageHeader.inventory.revision
            try seal.validate(context, row: row, inventory: inventory)
            try boundary(.beforeSave); try validate()
            let current = fresh(), currentInventory = try self.inventory(current)
            let repeated = try predecessor(request, context: current, inventory: currentInventory)
            guard let currentRow = try SharedMediaNativeReceivingPhaseGraph.row(request.packageID, in: current) else { throw SharedMediaStorageFailure.stale }
            try seal.requirePredecessor(row: currentRow, inventory: currentInventory)
            try requireSame(snapshot, repeated)
            try seal.validate(context, row: row, inventory: inventory); try validate()
            // No await or fence release between final validation and this save.
            let container = container, recoveryHeader = recoveryHeader
            try settlement.begin(admission) {
                try SharedMediaNativeReleaseStageRecovery.read(request, container: container, header: recoveryHeader)
            }
            do {
                try context.save(); try boundary(.afterSave)
            } catch {
                context.rollback()
                // A thrown save acknowledgement does not prove no save occurred.
                return try recover(request, exactSuccessor: true)
            }
            return try acknowledge(admission)
        } catch {
            context.rollback(); throw error
        }
    }

    private func predecessor(_ request: Request, context: ModelContext,
                             inventory: SharedMediaInventoryRecord) throws -> Reader.ProspectiveStageSnapshot {
        try validate()
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory, checkpoint: validate)
        try SharedMediaNativeReleaseStageIdentity.requireAbsent(request.releaseID, witnesses: Array(witnesses.values))
        try SharedMediaNativeTerminalScan.requireAbsent([request.releaseID], container: container, inventoryID: inventory.id)
        try SharedMediaNativeReleaseStageIdentity.direct(request.releaseID, context: context)
        let snapshot = try Reader.prospectiveStage(request, context: context, checkpoint: validate)
        guard snapshot.predecessor.components.recoveryPresentationData == nil else { throw SharedMediaStorageFailure.closed }
        let others = try PhotoPreparationPolicy.add(witnesses.values.map { try $0.remainingAdvances })
        let terminals = try SharedMediaNativeTerminalScan.read(container: context.container, inventoryID: inventory.id).remainingAdvances
        let needed = try PhotoPreparationPolicy.add([terminals, 2, snapshot.predecessor.components.progress.remainingAdvances, others])
        _ = try SharedMediaStoragePolicy.add(inventory.revision, needed)
        return snapshot
    }

    private func requireSame(_ a: Reader.ProspectiveStageSnapshot, _ b: Reader.ProspectiveStageSnapshot) throws {
        let x = a.predecessor, y = b.predecessor
        guard a.request == b.request, x.slot == y.slot, x.header == y.header,
              x.components.progress == y.components.progress, x.components.package == y.components.package,
              x.components.member == y.components.member, x.components.targetOrigins == y.components.targetOrigins,
              x.components.ownedOriginals == y.components.ownedOriginals,
              try x.components.pairs.map({ try SharedMediaNativeDraftEnvelope.bytes($0) }) == y.components.pairs.map({ try SharedMediaNativeDraftEnvelope.bytes($0) }),
              a.funding.historical == b.funding.historical, a.funding.staged == b.funding.staged,
              a.funding.release.projection == b.funding.release.projection else { throw SharedMediaStorageFailure.stale }
    }

    private func recover(_ request: Request, exactSuccessor: Bool) throws -> Saved {
        try boundary(.beforeReadback)
        let container = container, authority = authority
        let result = try SharedMediaNativeReleaseStageRecovery.read(request, container: container,
            exactSuccessor: exactSuccessor, header: { try authority.header(container) })
        try settlement.resolved(request)
        return result
    }
    private func acknowledge(_ admission: SharedMediaNativeReleaseStageAdmission) throws -> Saved {
        let request = admission.request
        try boundary(.beforeReadback)
        let result = try SharedMediaNativeReleaseStageRecovery.read(request, container: container,
            exactSuccessor: true, header: { try self.authority.header(self.container) })
        let context = fresh()
        guard result == .staged(request),
              let row = try SharedMediaNativeReceivingPhaseGraph.row(request.packageID, in: context) else {
            throw SharedMediaStorageFailure.closed
        }
        try Task.checkCancellation()
        guard try authority.header(container) == request.postStageHeader else { throw SharedMediaStorageFailure.stale }
        try settlement.acknowledgedStage(admission, row: .init(row))
        return result
    }
    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
    private func inventory(_ c: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = authority.profile.inventoryID
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
}
