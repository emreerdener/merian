import Foundation
import SwiftData

/// One fresh persistence boundary inside the retained receiving owner. Allocation
/// requests release coordinator locks; transfer/status operations retain them.
@MainActor
final class SharedMediaNativeAppPhotoAllocationOperations {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Snapshot = SharedMediaNativePhotoAllocationSnapshot
    private let container: ModelContainer
    private let authority: SharedMediaNativeAppOperationAuthority
    private let io: SharedMediaNativeOriginalIO
    private let sealTransfer: (SharedMediaPhotoRetirementInspection, SharedMediaNativePairCompletion?) throws -> Void
    private let expected: SharedMediaNativeAppEligibility.Header
    private let availableBytes: () throws -> Int64
    private let boundary: (SharedMediaNativeMetadataBoundary) throws -> Void
    private var consumed = false

    private init(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                 io: SharedMediaNativeOriginalIO, sealTransfer: @escaping (SharedMediaPhotoRetirementInspection, SharedMediaNativePairCompletion?) throws -> Void,
                 expected: SharedMediaNativeAppEligibility.Header, availableBytes: @escaping () throws -> Int64,
                 boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) {
        self.io = io; self.sealTransfer = sealTransfer
        self.container = container; self.authority = authority; self.expected = expected
        self.availableBytes = availableBytes; self.boundary = boundary
    }

    static func audited(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        io: SharedMediaNativeOriginalIO, sealTransfer: @escaping (SharedMediaPhotoRetirementInspection, SharedMediaNativePairCompletion?) throws -> Void,
                        availableBytes: @escaping () throws -> Int64,
                        boundary: @escaping (SharedMediaNativeMetadataBoundary) throws -> Void) async throws -> Self {
        let expected = try authority.header(container)
        _ = try await SharedMediaNativeScopedAudit(app: container, profile: authority.profile, expected: expected.inventory,
            check: { guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale } },
            betweenPages: { await Task.yield() }).run()
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
        return Self(container: container, authority: authority, io: io, sealTransfer: sealTransfer, expected: expected,
            availableBytes: availableBytes, boundary: boundary)
    }

    /// Discovery never creates a new attempt or changes the saved candidate.
    func saved(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation? {
        try validate(); guard prepared.profile == authority.profile else { throw SharedMediaStorageFailure.closed }
        let context = fresh(), inventory = try inventory(context)
        guard let witness = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)[prepared.package.id] else {
            throw SharedMediaStorageFailure.stale
        }
        switch witness {
        case .allocating(let snapshot):
            guard try snapshot.prepared.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
            return snapshot.allocation
        case .generic(let value):
            guard case .received(let p, _, _) = value.slot, try p.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.closed }
            return nil
        case .staged, .releasing: throw SharedMediaStorageFailure.closed
        }
    }

    func claim(_ prepared: SharedMediaNativeReceivingIntent.Prepared, attemptID: UUID, reserveRoleMapping: Bool = false, reserveBackendBinding: Bool = false, beforeClaimSave: () throws -> Void = {}) throws -> SharedMediaNativePhotoAllocationDispatch {
        if let saved = try saved(prepared) {
            let allocation = try reserveBackendBinding ? reserveRoles(prepared, backendBinding: true) : (reserveRoleMapping ? reserveRoles(prepared) : saved)
            return .init(allocation: allocation, create: false)
        }
        let context = fresh(), inventory = try inventory(context)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .generic(let value) = witnesses[prepared.package.id],
              case .received(let p, let received, _) = value.slot, try p.encoded() == prepared.encoded() else { throw SharedMediaStorageFailure.stale }
        let legacy = Allocation(claim: try .init(prepared: p, received: received, attemptID: attemptID))
        let allocation = try reserveBackendBinding ? legacy.reservingBackendBinding() : (reserveRoleMapping ? legacy.reservingRoleMapping() : legacy)
        try requireReservation(allocation, replacing: nil, context: context, inventory: inventory, witnesses: witnesses)
        let acknowledged = try persist(allocation, prepared: prepared, context: context, inventory: inventory, beforeSave: beforeClaimSave)
        // Exact readback of an uncertain acknowledgement deliberately mints no create authority.
        return .init(allocation: allocation, create: acknowledged)
    }

    /// Upgrade an existing claim only. Even an unresolved legacy claim can never
    /// regain create authority through reservation or acknowledgement recovery.
    func reserveRoles(_ prepared: SharedMediaNativeReceivingIntent.Prepared, backendBinding: Bool = false) throws -> Allocation {
        guard let current = try saved(prepared) else { throw SharedMediaStorageFailure.closed }
        let after = try backendBinding ? current.reservingBackendBinding() : current.reservingRoleMapping()
        guard after != current else { return current }
        let context = fresh(), inventory = try inventory(context)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .allocating(let snapshot) = witnesses[prepared.package.id], snapshot.allocation == current else {
            throw SharedMediaStorageFailure.stale
        }
        try requireReservation(after, replacing: current, context: context, inventory: inventory, witnesses: witnesses)
        _ = try persist(after, prepared: prepared, context: context, inventory: inventory)
        return after
    }

    func reserveTransfer(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                         selection: SharedMediaNativePhotoRoleMapping.Entry) throws -> Allocation {
        guard let current = try saved(prepared) else { throw SharedMediaStorageFailure.closed }
        let value = try SharedMediaNativePhotoTransferReservation(prepared: prepared, selection: selection)
        let after = try current.reservingTransfer(value)
        guard after != current else { return current }
        let context = fresh(), inventory = try inventory(context)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .allocating(let snapshot) = witnesses[prepared.package.id], snapshot.allocation == current else {
            throw SharedMediaStorageFailure.stale
        }
        try requireReservation(after, replacing: current, context: context, inventory: inventory, witnesses: witnesses)
        _ = try persist(after, prepared: prepared, context: context, inventory: inventory)
        return after
    }

    func reserveRemoteAttempt(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation {
        guard let current = try saved(prepared) else { throw SharedMediaStorageFailure.closed }
        return try saveRemoteAttempt(current.reservingRemoteAttempt(), replacing: current, prepared: prepared)
    }

    func reservePutStart(_ prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation {
        guard let current = try saved(prepared) else { throw SharedMediaStorageFailure.closed }
        return try saveRemoteAttempt(current.reservingPutStart(), replacing: current, prepared: prepared)
    }

    func observeRemoteAttempt(_ status: InitialPhotoUploadStatus, request: Allocation,
                              prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation {
        guard try saved(prepared) == request else { throw SharedMediaStorageFailure.stale }
        return try saveRemoteAttempt(request.observing(status), replacing: request, prepared: prepared)
    }

    /// One read-only query followed by at most one existing observation save.
    /// The retained account/receiving operation owns the complete transport drain.
    func recoverTransferStatus(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                               send: @MainActor (InitialPhotoTransferRequest, @escaping @MainActor @Sendable () throws -> Void) async throws -> Data) async throws -> Allocation {
        guard let current = try saved(prepared), let transfer = current.transferReservation else { throw SharedMediaStorageFailure.closed }
        let request = try InitialPhotoTransferRequest(allocation: current, action: .status)
        let check: @MainActor @Sendable () throws -> Void = {
            guard try self.saved(prepared) == current else { throw SharedMediaStorageFailure.stale }
        }
        try check()
        let bytes = try await send(request, check)
        try check()
        let status = try InitialPhotoUploadStatus(data: bytes, allocation: current, objectID: transfer.selection.objectID)
        return try observeRemoteAttempt(status, request: current, prepared: prepared)
    }

    /// Only the retained fresh-ticket composition may request this marker.
    /// Persistence ambiguity and recovered markers never mint a fresh continuation.
    private func beginTicketRequest(_ prepared: SharedMediaNativeReceivingIntent.Prepared, putReserved: Bool = false) throws -> SharedMediaNativePhotoTicketContinuation? {
        guard let current = try saved(prepared), putReserved ? (10...11).contains(current.version) : ((4...5).contains(current.version) || (8...9).contains(current.version)) else { throw SharedMediaStorageFailure.closed }
        guard putReserved ? current.version == 10 : (current.version == 4 || current.version == 8), current.remoteAttempt == nil else { return nil }
        let after = try current.startingTicketRequest()
        let context = fresh(), inventory = try inventory(context)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .allocating(let snapshot) = witnesses[prepared.package.id], snapshot.allocation == current else {
            throw SharedMediaStorageFailure.stale
        }
        try requireReservation(after, replacing: current, context: context, inventory: inventory, witnesses: witnesses)
        guard try persist(after, prepared: prepared, context: context, inventory: inventory) else { return nil }
        return .init(allocation: after, validate: { try self.readback(after, prepared: prepared) })
    }

    /// One fresh response within the original retained lease. Completion must
    /// open its next one-save operation under that same grant, not reacquire it.
    func withPutTicket(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                       catalog: InitialPhotoUploadDestination.Catalog,
                       send: @MainActor (InitialPhotoTransferRequest, @escaping @MainActor @Sendable () throws -> Void) async throws -> Data,
                       now: () -> Int64,
                       finish: @MainActor (SharedMediaNativePhotoTicketContinuation) async throws -> Int?) async throws -> Int? {
        guard let current = try saved(prepared), (10...12).contains(current.version) else { throw SharedMediaStorageFailure.closed }
        guard current.version == 10, current.remoteAttempt == nil, let binding = current.backendBinding else { return nil }
        let destination = try catalog.resolve(binding)
        let request = try InitialPhotoTransferRequest(allocation: current.startingTicketRequest(), action: .issue)
        guard let continuation = try beginTicketRequest(prepared, putReserved: true) else { return nil }
        defer { continuation.close() }
        guard continuation.allocation == request.allocation else { throw SharedMediaStorageFailure.stale }
        try continuation.consume()
        let bytes = try await send(request, { try continuation.validateConsumed() })
        let ticket = try continuation.decodeResponse(bytes, destination: destination, nowMilliseconds: now())
        guard ticket.outcome == .issued else { return nil }
        return try await finish(continuation)
    }

    func persistPut(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                    continuation: SharedMediaNativePhotoTicketContinuation) throws -> SharedMediaNativePhotoPutAuthorization? {
        guard let current = try saved(prepared), current.version == 11,
              current == continuation.allocation else { throw SharedMediaStorageFailure.stale }
        let ticket = try continuation.takeIssued()
        guard let attempt = ticket.issuedAttempt else { throw SharedMediaStorageFailure.closed }
        let after = try current.startingPut(attempt)
        let context = fresh(), inventory = try inventory(context)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .allocating(let snapshot) = witnesses[prepared.package.id], snapshot.allocation == current else {
            throw SharedMediaStorageFailure.stale
        }
        try requireReservation(after, replacing: current, context: context, inventory: inventory, witnesses: witnesses)
        guard try persist(after, prepared: prepared, context: context, inventory: inventory) else { return nil }
        return try .init(allocation: after, ticket: ticket, validate: { try self.readback(after, prepared: prepared) })
    }

    #if DEBUG
    /// Prepares the exact future wire request under the real owner. No HTTP or
    /// PUT is allowed here: V8/V9 have not reserved the later PUT-state save.
    func requestBoundTicketForTesting(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                                      catalog: InitialPhotoUploadDestination.Catalog,
                                      observe: @escaping @MainActor (InitialPhotoTransferRequest, InitialPhotoUploadDestination, SharedMediaNativePhotoTicketContinuation) async throws -> Void) async throws -> Bool {
        guard TestExecutionCoordinator.isRunningTests,
              let current = try saved(prepared), current.version == 8 || current.version == 9,
              let binding = current.backendBinding else { throw SharedMediaStorageFailure.closed }
        guard current.version == 8, current.remoteAttempt == nil else { return false }
        // Both resolution and bounded serialization finish before the marker save.
        let destination = try catalog.resolve(binding)
        let request = try InitialPhotoTransferRequest(allocation: current.startingTicketRequest(), action: .issue)
        guard let continuation = try beginTicketRequest(prepared) else { return false }
        defer { continuation.close() }
        guard continuation.allocation == request.allocation else { throw SharedMediaStorageFailure.stale }
        try continuation.consume()
        try await observe(request, destination, continuation)
        try continuation.validateConsumed()
        return true
    }

    /// Observes the real durable boundary without a network route or Release callback.
    func requestTicketForTesting(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                                 send: @escaping @MainActor (Allocation, SharedMediaNativePhotoTicketContinuation) async throws -> Void) async throws -> Bool {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        guard let continuation = try beginTicketRequest(prepared) else { return false }
        defer { continuation.close() }
        try continuation.consume()
        try await send(continuation.allocation, continuation)
        try continuation.validateConsumed()
        return true
    }
    #endif

    private func saveRemoteAttempt(_ after: Allocation, replacing current: Allocation,
                                   prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation {
        guard after != current else { return current }
        let context = fresh(), inventory = try inventory(context)
        let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory)
        guard case .allocating(let snapshot) = witnesses[prepared.package.id], snapshot.allocation == current else {
            throw SharedMediaStorageFailure.stale
        }
        try requireReservation(after, replacing: current, context: context, inventory: inventory, witnesses: witnesses)
        _ = try persist(after, prepared: prepared, context: context, inventory: inventory)
        return after
    }

    func verifyTransfer(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                        allocation: Allocation) async throws -> SharedMediaNativePhotoTransferReadback {
        guard try saved(prepared) == allocation,
              (3...5).contains(allocation.version) || (7...12).contains(allocation.version),
              let reservation = allocation.transferReservation else { throw SharedMediaStorageFailure.stale }
        let state = try SharedMediaNativePhotoTransferReadback.state(prepared, reservation: reservation, context: fresh())
        let (inspection, completion) = try await io.verifyTransfer(state, reservation: reservation)
        // The actor has returned only after its synchronous descriptor scopes
        // close. Recheck authority and exact saved state before publishing facts.
        guard try saved(prepared) == allocation,
              try SharedMediaNativePhotoTransferReadback.state(prepared, reservation: reservation, context: fresh()) == state else {
            throw SharedMediaStorageFailure.stale
        }
        try sealTransfer(inspection, completion)
        try validate()
        return .init(selection: reservation.selection, byteCount: inspection.file.byteCount, sha256: inspection.file.sha256)
    }

    /// Inactive concrete file handoff. A response code is only a local transport
    /// observation: it neither settles remote closure nor releases the hold.
    func uploadTransfer(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                        upload: SharedMediaNativePhotoUpload) async throws -> Int {
        let allocation = upload.allocation
        guard try saved(prepared) == allocation, (3...5).contains(allocation.version) || allocation.version == 12,
              let reservation = allocation.transferReservation else { throw SharedMediaStorageFailure.stale }
        let state = try SharedMediaNativePhotoTransferReadback.state(prepared, reservation: reservation, context: fresh())
        let result = try await io.uploadTransfer(state, reservation: reservation, upload: upload) {
            guard try self.saved(prepared) == allocation,
                  try SharedMediaNativePhotoTransferReadback.state(prepared, reservation: reservation, context: self.fresh()) == state else {
                throw SharedMediaStorageFailure.stale
            }
        }
        guard try saved(prepared) == allocation,
              try SharedMediaNativePhotoTransferReadback.state(prepared, reservation: reservation, context: fresh()) == state else {
            throw SharedMediaStorageFailure.stale
        }
        try sealTransfer(result.inspection, result.completion)
        try validate()
        return result.statusCode
    }

    private func requireReservation(_ allocation: Allocation, replacing oldAllocation: Allocation?,
        context: ModelContext, inventory: SharedMediaInventoryRecord,
        witnesses: [UUID: SharedMediaNativeReceivingCleanGraph.Witness]) throws {
        let charge = try allocation.storageCharge, oldCharge = try oldAllocation?.storageCharge ?? 0
        guard charge >= oldCharge else { throw SharedMediaStorageFailure.conflict }
        let packageID = allocation.claim.packageID
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context,
            inventory: inventory, ownerID: authority.profile.ownerID, format: .appV2)
        guard let old = budget.metadataByPackage[packageID], old >= oldCharge,
              try PhotoPreparationPolicy.add([old - oldCharge, charge]) <= PhotoPreparationPolicy.metadata else {
            throw SharedMediaStorageFailure.capacity
        }
        let package = try SharedMediaNativePairPlanGraph.one(context,
            FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        guard try PhotoPreparationPolicy.add([package.allocatedByteCount, old - oldCharge, charge]) <= PhotoPreparationPolicy.package else {
            throw SharedMediaStorageFailure.capacity
        }
        var totals = budget.totals
        try totals.includePhotoPhysical(materialized: 0, reserved: charge - oldCharge)
        if allocation.transferReservation != nil, oldAllocation?.transferReservation == nil {
            try totals.include(.init(packageID: packageID, pool: .transfer, materialized: 0,
                reserved: SharedMediaNativePhotoTransferReservation.copyAllowance))
        }
        try totals.checkAvailable(availableBytes())
        let terminal = try SharedMediaNativeTerminalScan.read(container: container, inventoryID: inventory.id).consumptionAdvances
        let peers = witnesses.filter { $0.key != packageID }.values
        let remaining = try PhotoPreparationPolicy.add([1, allocation.remainingAdvances, terminal] + peers.map { try $0.remainingAdvances })
        _ = try SharedMediaStoragePolicy.add(inventory.revision, remaining)
    }

    func settle(_ reply: InitialPhotoAllocationReply, request: Allocation,
                prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation {
        guard let current = try saved(prepared), current.claim == request.claim else { throw SharedMediaStorageFailure.stale }
        if let receipt = request.receipt, current.receipt != receipt { throw SharedMediaStorageFailure.conflict }
        switch reply {
        case .held: return current
        case .allocated(let receipt):
            let after = try current.settling(receipt)
            guard after != current else { return current }
            let context = fresh(), inventory = try inventory(context)
            guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else {
                throw SharedMediaStorageFailure.stale
            }
            let snapshot = try Snapshot.read(.init(row), inventory: inventory, context: context)
            guard snapshot.allocation == current else { throw SharedMediaStorageFailure.stale }
            guard try after.storageCharge <= current.storageCharge else { throw SharedMediaStorageFailure.capacity }
            _ = try persist(after, prepared: prepared, context: context, inventory: inventory)
            return after
        }
    }

    /// Persist the complete mapping atomically, only against a durably reserved
    /// request. Holds and exact replays do not save or release any liability.
    func enrich(_ reply: InitialPhotoAllocationRoleReply, request: Allocation,
                prepared: SharedMediaNativeReceivingIntent.Prepared) throws -> Allocation {
        guard request.version == 2 || request.version == 6, let current = try saved(prepared), current.version == request.version,
              current.claim == request.claim else { throw SharedMediaStorageFailure.stale }
        if let receipt = request.receipt, receipt != current.receipt { throw SharedMediaStorageFailure.conflict }
        if let mapping = request.roleMapping, mapping != current.roleMapping { throw SharedMediaStorageFailure.conflict }
        if let binding = request.backendBinding, binding != current.backendBinding { throw SharedMediaStorageFailure.conflict }
        guard case .allocated(let projection) = reply else { return current }
        let after = try current.enriching(projection.receipt, mapping: .init(entries: projection.entries), binding: projection.backendBinding)
        guard after != current else { return current }
        let context = fresh(), inventory = try inventory(context)
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context),
              try Snapshot.read(.init(row), inventory: inventory, context: context).allocation == current else {
            throw SharedMediaStorageFailure.stale
        }
        guard try after.storageCharge <= current.storageCharge else { throw SharedMediaStorageFailure.capacity }
        _ = try persist(after, prepared: prepared, context: context, inventory: inventory)
        return after
    }

    /// Returns true only for a successful save acknowledgement and exact fresh
    /// readback. Any ambiguity permanently spends this operation's create right.
    private func persist(_ allocation: Allocation, prepared: SharedMediaNativeReceivingIntent.Prepared,
                         context: ModelContext, inventory: SharedMediaInventoryRecord, beforeSave: () throws -> Void = {}) throws -> Bool {
        try validate()
        guard !consumed, let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else {
            throw SharedMediaStorageFailure.closed
        }
        let seal = try SharedMediaNativePhotoAllocationPoststate(row: row, inventory: inventory, after: allocation, context: context)
        do {
            row.allocationData = try allocation.encoded()
            row.allocationSHA256 = SharedMediaAcquisitionEncoding.digest(row.allocationData!)
            inventory.revision = try SharedMediaStoragePolicy.add(expected.inventory.revision, 1)
            try seal.validate(context, row: row, inventory: inventory)
            try boundary(.beforeSave); try validate()
            let check = fresh(), currentInventory = try self.inventory(check)
            guard let currentRow = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: check) else {
                throw SharedMediaStorageFailure.stale
            }
            try seal.requirePredecessor(row: currentRow, inventory: currentInventory)
            // Recheck whole pending runway immediately before save, without an await.
            let witnesses = try SharedMediaNativeReceivingCleanGraph.pending(check, inventory: currentInventory)
            let predecessor: Allocation?
            if let data = currentRow.allocationData, let sha = currentRow.allocationSHA256 {
                predecessor = try Allocation.decode(data, sha256: sha)
            } else { predecessor = nil }
            if predecessor == nil || predecessor?.version != allocation.version || allocation.version >= 4 {
                try requireReservation(allocation, replacing: predecessor, context: check,
                    inventory: currentInventory, witnesses: witnesses)
            }
            try seal.validate(context, row: row, inventory: inventory); try validate()
            try beforeSave()
            consumed = true
            do {
                try context.save(); try boundary(.afterSave)
            } catch {
                context.rollback()
                try readback(allocation, prepared: prepared)
                return false
            }
            try readback(allocation, prepared: prepared)
            return true
        } catch { context.rollback(); throw error }
    }

    private func readback(_ allocation: Allocation, prepared: SharedMediaNativeReceivingIntent.Prepared) throws {
        try boundary(.beforeReadback)
        let header = try authority.header(container)
        guard header == (try SharedMediaNativeAppMetadataFacts.successor(expected)) else { throw SharedMediaStorageFailure.stale }
        let context = fresh(), inventory = try inventory(context)
        guard let row = try SharedMediaNativeReceivingPhaseGraph.row(prepared.package.id, in: context) else { throw SharedMediaStorageFailure.stale }
        let snapshot = try Snapshot.read(.init(row), inventory: inventory, context: context)
        guard try snapshot.prepared.encoded() == prepared.encoded(), snapshot.allocation == allocation else { throw SharedMediaStorageFailure.stale }
        _ = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context, inventory: inventory,
            ownerID: authority.profile.ownerID, format: .appV2)
        guard try authority.header(container) == header else { throw SharedMediaStorageFailure.stale }
    }

    private func validate() throws {
        guard try authority.header(container) == expected else { throw SharedMediaStorageFailure.stale }
    }
    private func fresh() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
    private func inventory(_ context: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = authority.profile.inventoryID
        return try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
}

/// Volatile, single-use disposition minted only by the acknowledged claim owner.
@MainActor
final class SharedMediaNativePhotoAllocationDispatch {
    let allocation: SharedMediaNativePhotoAllocation
    private let create: Bool
    private var consumed = false
    fileprivate init(allocation: SharedMediaNativePhotoAllocation, create: Bool) {
        self.allocation = allocation; self.create = create
    }
    func consume(projection: InitialPhotoAllocationRequest.Projection = .legacy) throws -> InitialPhotoAllocationRequest {
        guard !consumed else { throw SharedMediaStorageFailure.closed }
        consumed = true
        return try .init(allocation: allocation, action: create ? .create : .status, projection: projection)
    }
}

/// Volatile, one-shot right bound to the exact saved successor and retained
/// account/receiving operation. No decoded state can construct this value.
@MainActor
final class SharedMediaNativePhotoTicketContinuation {
    let allocation: SharedMediaNativePhotoAllocation
    private var check: (() throws -> Void)?
    private var consumed = false
    private var closed = false
    private var responseConsumed = false
    private var issuedTicket: InitialPhotoUploadTicket?
    fileprivate init(allocation: SharedMediaNativePhotoAllocation, validate: @escaping () throws -> Void) {
        self.allocation = allocation; check = validate
    }
    func consume() throws {
        guard !closed, !consumed, let check else { throw SharedMediaStorageFailure.closed }
        consumed = true
        try check()
    }
    func validateConsumed() throws {
        guard !closed, consumed, let check else { throw SharedMediaStorageFailure.closed }
        try check()
    }
    /// One response observation while the exact receiving/account operation is
    /// retained. This never constructs a request or promotes metadata to PUT authority.
    func decodeResponse(_ data: Data, destination: InitialPhotoUploadDestination,
                        nowMilliseconds: Int64) throws -> InitialPhotoUploadTicket {
        try validateConsumed()
        guard !responseConsumed else { throw SharedMediaStorageFailure.closed }
        responseConsumed = true
        let result = try InitialPhotoUploadTicket(data: data, allocation: allocation,
            destination: destination, nowMilliseconds: nowMilliseconds)
        try validateConsumed()
        if allocation.version == 11, result.outcome == .issued { issuedTicket = result }
        return result
    }
    fileprivate func takeIssued() throws -> InitialPhotoUploadTicket {
        let ticket = issuedTicket; issuedTicket = nil
        defer { close() }
        try validateConsumed()
        guard allocation.version == 11, let ticket else { throw SharedMediaStorageFailure.closed }
        return ticket
    }
    fileprivate func close() {
        closed = true
        // A closed handle must not retain the repository's file ownership.
        check = nil; issuedTicket = nil
    }
}

/// Volatile grant minted only by a freshly consumed response and acknowledged
/// V12 save. Decoded records and arbitrary tickets cannot construct this value.
@MainActor
final class SharedMediaNativePhotoPutAuthorization {
    let allocation: SharedMediaNativePhotoAllocation
    private var ticket: InitialPhotoUploadTicket?
    private var check: (() throws -> Void)?
    private var consumed = false
    fileprivate init(allocation: SharedMediaNativePhotoAllocation, ticket: InitialPhotoUploadTicket,
                     validate: @escaping () throws -> Void) throws {
        try ticket.requirePutSuccessor(allocation)
        self.allocation = allocation; self.ticket = ticket; check = validate
    }
    func request(nowMilliseconds: Int64) throws -> (URLRequest, Int64) {
        guard let ticket else { throw SharedMediaStorageFailure.closed }
        return try ticket.authorizedRequest(self, nowMilliseconds: nowMilliseconds)
    }
    func consume(matching candidate: InitialPhotoUploadTicket) throws {
        let fresh = ticket; ticket = nil
        guard !consumed else { throw SharedMediaStorageFailure.closed }; consumed = true
        guard let fresh, fresh.matches(candidate), let check else { throw SharedMediaStorageFailure.closed }
        try check()
    }
    func validateConsumed() throws {
        guard consumed, let check else { throw SharedMediaStorageFailure.closed }
        try check()
    }
    func close() { ticket = nil; check = nil; consumed = true }
}
