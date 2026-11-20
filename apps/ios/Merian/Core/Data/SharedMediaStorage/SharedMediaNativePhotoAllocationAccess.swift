import Foundation

/// Caller composition only. The retained owner decides create versus status;
/// authorization never substitutes for its persisted claim and account fences.
struct SharedMediaNativePhotoAllocationAccess {
    typealias Validator = @MainActor @Sendable () throws -> Void
    typealias Authorize = @MainActor (SharedMediaNativeReceivingIntent.Prepared, @escaping Validator) async throws -> IdentificationDispatchAuthorization
    typealias Send = @MainActor (InitialPhotoAllocationRequest, @escaping Validator, @escaping Validator) async throws -> InitialPhotoAllocationReply
    let authorize: Authorize
    private let transport: NativePhotoAllocationTransportAccess
    init(authorize: @escaping Authorize, send: @escaping Send) {
        self.authorize = authorize; transport = .legacy(send)
    }
    init(authorize: @escaping Authorize, sendRoles: @escaping NativePhotoAllocationTransportAccess.RolesSend) {
        self.authorize = authorize; transport = .roles(sendRoles)
    }

    init(authorize: @escaping Authorize, sendBoundRoles: @escaping NativePhotoAllocationTransportAccess.RolesSend) {
        self.authorize = authorize; transport = .boundRoles(sendBoundRoles)
    }

    /// Explicit recovery only. Never calls authorize or the create-capable owner.
    @MainActor func recover(owner: SharedMediaNativeOriginalOwner,
                            prepared: SharedMediaNativeReceivingIntent.Prepared,
                            validate: @escaping Validator) async throws -> SharedMediaNativePhotoAllocation {
        let scoped: NativePhotoAllocationTransportAccess
        switch transport {
        case .legacy(let send):
            scoped = .legacy { request, check, settle in
                try validate()
                let reply = try await send(request, { try check(); try validate() }, { try settle(); try validate() })
                try validate()
                return reply
            }
        case .roles(let send), .boundRoles(let send):
            let wrapped: NativePhotoAllocationTransportAccess.RolesSend = { request, check, settle in
                try validate()
                let reply = try await send(request, { try check(); try validate() }, { try settle(); try validate() })
                try validate()
                return reply
            }
            scoped = transport.projection == .boundRoles ? .boundRoles(wrapped) : .roles(wrapped)
        }
        try validate()
        let result = try await owner.recoverAppPhotoAllocationStatus(prepared, transport: scoped)
        try validate()
        return result
    }

    /// Neither saved rows nor a caller-provided Bool can construct a fresh start.
    @MainActor final class FreshReceive {
        fileprivate weak var owner: SharedMediaNativeOriginalOwner?
        fileprivate let prepared: SharedMediaNativeReceivingIntent.Prepared
        fileprivate init(_ owner: SharedMediaNativeOriginalOwner, _ prepared: SharedMediaNativeReceivingIntent.Prepared) {
            self.owner = owner; self.prepared = prepared
        }
    }
    typealias ReadTerminalAllocation = @MainActor @Sendable () throws -> SharedMediaNativePhotoAllocation

    struct CohortAdmission {
        let verify: @MainActor (VerificationStart) async throws -> Bool
        let readOriginal: @MainActor (SharedMediaNativePhotoAllocation, @escaping Validator) async throws -> Data?
    }
    /// Minted by the original submit flow only after its terminal save returned
    /// positively. Cold reads of the same V17 row can only recover admission.
    @MainActor final class VerificationStart {
        private var original: ReadTerminalAllocation?
        private var spent = false
        fileprivate init(_ original: @escaping ReadTerminalAllocation) { self.original = original }
        func consume() throws -> SharedMediaNativePhotoAllocation {
            guard !spent, let original else { throw SharedMediaStorageFailure.closed }
            spent = true
            return try original()
        }
        func validate() throws {
            guard spent, let original else { throw SharedMediaStorageFailure.closed }
            _ = try original()
        }
        fileprivate func close() { original = nil; spent = true }
    }
    @MainActor final class FirstStart {
        private weak var owner: SharedMediaNativeOriginalOwner?
        private let prepared: SharedMediaNativeReceivingIntent.Prepared
        private var allocation: SharedMediaNativePhotoAllocation?
        private let authorize: Authorize
        private var authorizationBegan = false
        private var current: Validator?
        private var transferReader: InitialPhotoTransferRequest.Send?
        fileprivate var admission: CohortAdmission?
        fileprivate init(_ receive: FreshReceive, _ allocation: SharedMediaNativePhotoAllocation, authorize: @escaping Authorize) {
            self.owner = receive.owner; self.prepared = receive.prepared; self.allocation = allocation; self.authorize = authorize
        }
        func authorizeStart(_ caller: @escaping Validator, send: @escaping InitialPhotoTransferRequest.Send, admission: CohortAdmission?) async throws {
            guard !authorizationBegan, allocation != nil else { throw SharedMediaStorageFailure.closed }; authorizationBegan = true
            try caller()
            let auth = try await authorize(prepared, caller)
            try caller(); try SharedMediaNativePhotoAdmission(authorization: auth).requireSaved(prepared.photoAdmission)
            current = { try caller(); try auth.validate() }
            transferReader = send
            self.admission = admission
            try validate()
        }
        func validate() throws {
            guard let current, owner != nil else { throw SharedMediaStorageFailure.closed }
            try current()
        }
        /// This caller retains its original consent check and authenticated
        /// reader. A saved local receipt alone cannot construct ConfirmedRole.
        func confirm(_ value: SharedMediaNativeReceivingIntent.Prepared,
                     on operation: NativeAppPhotoAllocationOperations) async throws -> ConfirmedRole? {
            try validate()
            guard allocation == nil, try prepared.encoded() == value.encoded(), let transferReader else {
                throw SharedMediaStorageFailure.stale
            }
            var acknowledged = false
            let after = try await operation.retainRoleProgress(value, beforeObservationSave: validate,
                onAcknowledged: { acknowledged = true }, send: InitialPhotoTransferRequest.validating(transferReader, { try self.validate() }))
            try validate()
            return acknowledged ? ConfirmedRole(after, origin: self) : nil
        }
        fileprivate func take(_ value: SharedMediaNativeReceivingIntent.Prepared, owner: SharedMediaNativeOriginalOwner) throws -> SharedMediaNativePhotoAllocation {
            try validate()
            guard self.owner === owner, try prepared.encoded() == value.encoded(), let allocation else { throw SharedMediaStorageFailure.stale }
            self.allocation = nil; return allocation
        }
    }
    @MainActor final class ConfirmedRole {
        private let allocation: SharedMediaNativePhotoAllocation
        private let origin: FirstStart
        private var spent = false
        fileprivate init(_ allocation: SharedMediaNativePhotoAllocation, origin: FirstStart) {
            self.allocation = allocation
            self.origin = origin
        }
        func take(for start: FirstStart, current: SharedMediaNativePhotoAllocation) throws {
            guard !spent, origin === start, allocation == current else { throw SharedMediaStorageFailure.stale }
            spent = true
            try origin.validate()
        }
    }
    @MainActor static func receive(_ prepared: SharedMediaNativeReceivingIntent.Prepared, owner: SharedMediaNativeOriginalOwner) async throws -> (SharedMediaNativeConsumerCohort, FreshReceive?) {
        var issued: FreshReceive?
        let cohort = try await owner.receiveAppPrepared(prepared) { issued = FreshReceive(owner, prepared) }
        return (cohort, issued)
    }

    /// Preserve the caller's immutable selection/attempt fence around both
    /// projections. Only the retained owner decides durable create versus status.
    @MainActor func allocate(owner: SharedMediaNativeOriginalOwner,
                             prepared: SharedMediaNativeReceivingIntent.Prepared,
                             validate: @escaping Validator,
                             freshReceive: FreshReceive? = nil, onFirstStart: @escaping @MainActor (FirstStart) -> Void = { _ in }) async throws -> SharedMediaNativePhotoAllocation {
        let authorizeCreate: Authorize = { value, check in
            try validate(); try check()
            return try await authorize(value, { try check(); try validate() })
        }
        switch transport {
        case .legacy(let send):
            return try await owner.allocateAppPhoto(prepared, authorizeCreate: authorizeCreate) { request, check, settle in
                try validate()
                return try await send(request, { try check(); try validate() }, { try settle(); try validate() })
            }
        case .roles(let send), .boundRoles(let send):
            var acknowledged = false
            let result = try await owner.allocateAppPhotoRoles(prepared, backendBinding: transport.projection == .boundRoles, onBoundCreateSave: { acknowledged = true }, authorizeCreate: authorizeCreate) { request, check, settle in
                try validate()
                return try await send(request, { try check(); try validate() }, { try settle(); try validate() })
            }
            if acknowledged, result.version == 6, let freshReceive, freshReceive.owner === owner,
               try freshReceive.prepared.encoded() == prepared.encoded() {
                onFirstStart(FirstStart(freshReceive, result, authorize: authorize)); freshReceive.owner = nil
            }
            return result
        }
    }
}

/// Selects a typed projection without changing the retained owner's lifecycle.
/// Construction alone confers no create permission or durable reservation.
enum NativePhotoAllocationTransportAccess {
    typealias RolesSend = @MainActor (InitialPhotoAllocationRequest, @escaping SharedMediaNativePhotoAllocationAccess.Validator, @escaping SharedMediaNativePhotoAllocationAccess.Validator) async throws -> InitialPhotoAllocationRoleReply
    case legacy(SharedMediaNativePhotoAllocationAccess.Send)
    case roles(RolesSend)
    case boundRoles(RolesSend)
    var projection: InitialPhotoAllocationRequest.Projection {
        switch self {
        case .legacy: .legacy
        case .roles: .roles
        case .boundRoles: .boundRoles
        }
    }
    enum Reply { case legacy(InitialPhotoAllocationReply), roles(InitialPhotoAllocationRoleReply) }
    @MainActor func send(_ request: InitialPhotoAllocationRequest,
                         validate: @escaping SharedMediaNativePhotoAllocationAccess.Validator,
                         settle: @escaping SharedMediaNativePhotoAllocationAccess.Validator) async throws -> Reply {
        switch self {
        case .legacy(let send): return .legacy(try await send(request, validate, settle))
        case .roles(let send), .boundRoles(let send): return .roles(try await send(request, validate, settle))
        }
    }
}

extension NativeAppPhotoAllocationOperations {
    /// Recovery cannot create or upgrade a claim. The saved format selects its
    /// original response projection; no persistence occurs before the status await.
    func recoverAllocationStatus(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                                 transport: NativePhotoAllocationTransportAccess) async throws -> Allocation {
        guard let current = try saved(prepared) else { throw SharedMediaStorageFailure.closed }
        let projection: InitialPhotoAllocationRequest.Projection
        switch current.version {
        case 1: projection = .legacy
        case 2: projection = .roles
        case 6: projection = .boundRoles
        default: throw SharedMediaStorageFailure.closed
        }
        guard transport.projection == projection else { throw SharedMediaStorageFailure.closed }
        let request = try InitialPhotoAllocationRequest(allocation: current, action: .status, projection: projection)
        let check: @MainActor @Sendable () throws -> Void = {
            guard try self.saved(prepared) == current else { throw SharedMediaStorageFailure.stale }
        }
        try check()
        let reply = try await transport.send(request, validate: check, settle: check)
        try check()
        switch reply {
        case .legacy(let value): return try settle(value, request: current, prepared: prepared)
        case .roles(let value): return try enrich(value, request: current, prepared: prepared)
        }
    }

    /// One read-only query followed by at most one existing observation save.
    /// The retained account/receiving operation owns the complete transport drain.
    func recoverTransferStatus(_ prepared: SharedMediaNativeReceivingIntent.Prepared, beforeObservationSave: @MainActor () throws -> Void = {},
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
        try beforeObservationSave()
        return try observeRemoteAttempt(status, request: current, prepared: prepared)
    }

    /// Re-open the same durable allocation on either side of the authenticated
    /// read. This observation never issues a ticket or releases a copy allowance.
    func readRoleProgress(_ prepared: SharedMediaNativeReceivingIntent.Prepared,
                          send: InitialPhotoTransferRequest.Send) async throws -> InitialPhotoRoleProgress {
        guard let current = try saved(prepared) else { throw SharedMediaStorageFailure.closed }
        let request = try InitialPhotoTransferRequest(allocation: current, action: .roleProgress)
        let check: @MainActor @Sendable () throws -> Void = {
            guard try self.saved(prepared) == current else { throw SharedMediaStorageFailure.stale }
        }
        let bytes = try await send(request, check)
        try check()
        return try InitialPhotoRoleProgress(data: bytes, matching: request)
    }
}

extension NativeAppPhotoAllocationOperations {
    /// One held account/receiving operation. A recovered reservation can be
    /// inspected but can never enter this fresh V6 source-role start.
    static func prepareFirstTransfer(_ prepared: SharedMediaNativeReceivingIntent.Prepared, start: SharedMediaNativePhotoAllocationAccess.FirstStart, owner: SharedMediaNativeOriginalOwner, catalog: InitialPhotoUploadDestination.Catalog,
                                     open: @escaping @MainActor () async throws -> NativeAppPhotoAllocationOperations,
                                     validate: SharedMediaNativePhotoAllocationAccess.Validator) async throws -> Allocation {
        try validate(); let expected = try start.take(prepared, owner: owner)
        guard expected.version == 6, let binding = expected.backendBinding, let receipt = expected.receipt,
              let entry = expected.roleMapping?.entries.first, entry.photoOrdinal == 0, entry.role == .source else {
            throw SharedMediaStorageFailure.closed
        }
        _ = try catalog.resolve(binding)
        let first = try await open()
        try validate()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard (receipt.createdAtMilliseconds..<receipt.expiresAtMilliseconds).contains(now), try first.saved(prepared) == expected else { throw SharedMediaStorageFailure.stale }
        let held = try first.reserveTransfer(prepared, selection: entry)
        let remoteSlot = try await open()
        try validate()
        guard try remoteSlot.saved(prepared) == held else { throw SharedMediaStorageFailure.stale }
        let remote = try remoteSlot.reserveRemoteAttempt(prepared)
        let putSlot = try await open()
        try validate()
        guard try putSlot.saved(prepared) == remote else { throw SharedMediaStorageFailure.stale }
        return try putSlot.reservePutStart(prepared)
    }
}

extension NativeAppPhotoAllocationOperations {
    enum FollowingRoleStep {
        case ticket(SharedMediaNativePhotoTicketContinuation)
        case complete(SharedMediaNativePhotoAllocationAccess.ReadTerminalAllocation)
        case held
    }
    typealias NextRoleStart = @MainActor (NativeAppPhotoAllocationOperations, SharedMediaNativePhotoAllocationAccess.ConfirmedRole) throws -> FollowingRoleStep

    func sendPutTicket(_ continuation: SharedMediaNativePhotoTicketContinuation, request: InitialPhotoTransferRequest,
                       destination: InitialPhotoUploadDestination,
                       send: InitialPhotoTransferRequest.Send, now: () -> Int64,
                       finish: @MainActor (SharedMediaNativePhotoTicketContinuation) async throws -> Int?) async throws -> Int? {
        defer { continuation.close() }
        guard continuation.allocation == request.allocation else { throw SharedMediaStorageFailure.stale }
        try continuation.consume()
        let bytes = try await send(request.bindingFreshExchange(continuation), { try continuation.validateConsumed() })
        let ticket = try continuation.decodeResponse(bytes, destination: destination, nowMilliseconds: now())
        guard ticket.outcome == .issued else { return nil }
        return try await finish(continuation)
    }
    /// The receiving owner retains the same locks and grant for the bounded
    /// roster. Only the previous task's consumed retirement and a fresh local
    /// save can mint a continuation for a later member.
    static func transferAssigned(_ prepared: SharedMediaNativeReceivingIntent.Prepared, first: Allocation?, start: SharedMediaNativePhotoAllocationAccess.FirstStart?, request: NativeAppPhotoAllocationOperations,
                                 open: @escaping @MainActor () async throws -> NativeAppPhotoAllocationOperations,
                                 catalog: InitialPhotoUploadDestination.Catalog, send: @escaping InitialPhotoTransferRequest.Send,
                                 makeTask: @escaping @MainActor () -> PinnedPhotoUploadTask,
                                 validate: @escaping SharedMediaNativePhotoAllocationAccess.Validator) async throws -> Int? {
        let members = first?.roleMapping?.entries.count ?? 1
        guard (1...6).contains(members) else { throw SharedMediaStorageFailure.conflict }
        let scoped = InitialPhotoTransferRequest.validating(send, validate)
        let now = { Int64(Date().timeIntervalSince1970 * 1000) }
        var next: SharedMediaNativePhotoTicketContinuation?
        defer { next?.close() }
        for index in 0..<members {
            var handoff: (NextRoleStart, SharedMediaNativePhotoAllocationAccess.ConfirmedRole)?
            let consume: @MainActor (SharedMediaNativePhotoTicketContinuation) async throws -> Int? = { ticket in
                let persist = try await open()
                try validate()
                guard let authority = try persist.persistPut(prepared, continuation: ticket) else { return nil }
                defer { authority.close() }
                let upload = try SharedMediaNativePhotoUpload.authorized(authority, task: makeTask(),
                    nowMilliseconds: now(), validateCaller: validate)
                return try await consumeAndObserve(prepared, upload: upload, start: start,
                    open: open, send: scoped, validate: validate, ready: { handoff = ($0, $1) })
            }
            try validate()
            let status: Int?
            if index == 0 {
                status = try await request.withPutTicket(prepared, catalog: catalog, send: scoped, now: now, finish: consume)
            } else {
                guard let ticket = next, ticket.allocation.version == 14, let backend = ticket.allocation.backendBinding else {
                    throw SharedMediaStorageFailure.closed
                }
                next = nil
                defer { ticket.close() }
                let owner = try await open()
                try validate()
                guard try owner.saved(prepared) == ticket.allocation else { throw SharedMediaStorageFailure.stale }
                status = try await owner.sendPutTicket(ticket, request: InitialPhotoTransferRequest(allocation: ticket.allocation, action: .issue),
                    destination: catalog.resolve(backend), send: scoped, now: now, finish: consume)
            }
            guard let handoff else { return start == nil ? status : nil }
            let advance = try await open()
            try validate()
            switch try handoff.0(advance, handoff.1) {
            case .complete(let terminal):
                guard index + 1 == members else { throw SharedMediaStorageFailure.conflict }
                if let admission = start?.admission {
                    let grant = SharedMediaNativePhotoAllocationAccess.VerificationStart(terminal)
                    defer { grant.close() }
                    guard try await admission.verify(grant) else { return nil }
                    // The returned admission indication has no durable authority.
                    // Read and pin the original server acknowledgement separately.
                    try grant.validate()
                    let pin = try await open()
                    let recovered = try await pin.recoverInitialAdmission(prepared, caller: validate) { value, check in
                        try grant.validate()
                        guard value == (try terminal()) else { throw SharedMediaStorageFailure.stale }
                        let bytes = try await admission.readOriginal(value, { try check(); try grant.validate() })
                        try check(); try grant.validate()
                        return bytes
                    }
                    try validate()
                    guard recovered != nil else { return nil }
                }
                return status
            case .held: return nil
            case .ticket(let granted):
                next = granted
                guard index + 1 < members else { throw SharedMediaStorageFailure.conflict }
            }
        }
        throw SharedMediaStorageFailure.conflict
    }

    /// A fresh, explicitly composed Capture upload checks the exact attempt once.
    /// No server observation, delayed close or lost answer schedules another PUT.
    static func consumeAndObserve(_ prepared: SharedMediaNativeReceivingIntent.Prepared, upload: SharedMediaNativePhotoUpload,
                                  start: SharedMediaNativePhotoAllocationAccess.FirstStart?, open: @escaping @MainActor () async throws -> NativeAppPhotoAllocationOperations,
                                  send: @escaping InitialPhotoTransferRequest.Send,
                                  validate: @escaping SharedMediaNativePhotoAllocationAccess.Validator, ready: (@escaping NextRoleStart, SharedMediaNativePhotoAllocationAccess.ConfirmedRole) -> Void) async throws -> Int {
        let consume = try await open()
        var localEnd: NextRoleStart?
        let status = try await consume.uploadTransfer(prepared, upload: upload, start: start, retired: { localEnd = $0 })
        guard let start, (200..<300).contains(status) else { return status }
        try validate()
        let original = upload.allocation, query = try await open()
        try validate()
        guard original.transferPhase == 12, try query.saved(prepared) == original else { throw SharedMediaStorageFailure.stale }
        let read = InitialPhotoTransferRequest.validating(send, validate)
        let observed = try await query.recoverTransferStatus(prepared, beforeObservationSave: validate, send: read)
        try validate()
        guard observed.remoteAttempt?.writeClosed == true else { return status }
        let retain = try await open()
        try validate()
        guard try retain.saved(prepared) == observed else { throw SharedMediaStorageFailure.stale }
        let confirmation = try await start.confirm(prepared, on: retain)
        try validate()
        if let confirmation, let localEnd { ready(localEnd, confirmation) }
        return status
    }
}
