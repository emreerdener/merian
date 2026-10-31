import Foundation

/// Caller composition only. The retained owner decides create versus status;
/// authorization never substitutes for its persisted claim and account fences.
struct SharedMediaNativePhotoAllocationAccess {
    typealias Validator = @MainActor @Sendable () throws -> Void
    typealias Authorize = @MainActor (SharedMediaNativeReceivingIntent.Prepared, @escaping Validator) async throws -> IdentificationDispatchAuthorization
    typealias Send = @MainActor (InitialPhotoAllocationRequest, @escaping Validator, @escaping Validator) async throws -> InitialPhotoAllocationReply
    let authorize: Authorize
    private let transport: SharedMediaNativePhotoAllocationTransportAccess
    init(authorize: @escaping Authorize, send: @escaping Send) {
        self.authorize = authorize; transport = .legacy(send)
    }
    init(authorize: @escaping Authorize, sendRoles: @escaping SharedMediaNativePhotoAllocationTransportAccess.RolesSend) {
        self.authorize = authorize; transport = .roles(sendRoles)
    }

    init(authorize: @escaping Authorize, sendBoundRoles: @escaping SharedMediaNativePhotoAllocationTransportAccess.RolesSend) {
        self.authorize = authorize; transport = .boundRoles(sendBoundRoles)
    }

    /// Explicit recovery only. Never calls authorize or the create-capable owner.
    @MainActor func recover(owner: SharedMediaNativeOriginalOwner,
                            prepared: SharedMediaNativeReceivingIntent.Prepared,
                            validate: @escaping Validator) async throws -> SharedMediaNativePhotoAllocation {
        let scoped: SharedMediaNativePhotoAllocationTransportAccess
        switch transport {
        case .legacy(let send):
            scoped = .legacy { request, check, settle in
                try validate()
                let reply = try await send(request, { try check(); try validate() }, { try settle(); try validate() })
                try validate()
                return reply
            }
        case .roles(let send), .boundRoles(let send):
            let wrapped: SharedMediaNativePhotoAllocationTransportAccess.RolesSend = { request, check, settle in
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

    /// Preserve the caller's immutable selection/attempt fence around both
    /// projections. Only the retained owner decides durable create versus status.
    @MainActor func allocate(owner: SharedMediaNativeOriginalOwner,
                             prepared: SharedMediaNativeReceivingIntent.Prepared,
                             validate: @escaping Validator) async throws -> SharedMediaNativePhotoAllocation {
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
            return try await owner.allocateAppPhotoRoles(prepared, backendBinding: transport.projection == .boundRoles, authorizeCreate: authorizeCreate) { request, check, settle in
                try validate()
                return try await send(request, { try check(); try validate() }, { try settle(); try validate() })
            }
        }
    }
}

/// Selects a typed projection without changing the retained owner's lifecycle.
/// Construction alone confers no create permission or durable reservation.
enum SharedMediaNativePhotoAllocationTransportAccess {
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
