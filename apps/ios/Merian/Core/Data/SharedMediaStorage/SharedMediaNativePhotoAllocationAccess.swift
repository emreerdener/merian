import Foundation

/// Caller composition only. The retained owner decides create versus status;
/// authorization never substitutes for its persisted claim and account fences.
struct SharedMediaNativePhotoAllocationAccess {
    typealias Validator = @MainActor @Sendable () throws -> Void
    typealias Authorize = @MainActor (SharedMediaNativeReceivingIntent.Prepared, @escaping Validator) async throws -> IdentificationDispatchAuthorization
    typealias Send = @MainActor (InitialPhotoAllocationRequest, @escaping Validator, @escaping Validator) async throws -> InitialPhotoAllocationReply
    let authorize: Authorize
    let send: Send
}

/// Selects a typed projection without changing the retained owner's lifecycle.
/// Construction alone confers no create permission or durable reservation.
enum SharedMediaNativePhotoAllocationTransportAccess {
    typealias RolesSend = @MainActor (InitialPhotoAllocationRequest, @escaping SharedMediaNativePhotoAllocationAccess.Validator, @escaping SharedMediaNativePhotoAllocationAccess.Validator) async throws -> InitialPhotoAllocationRoleReply
    case legacy(SharedMediaNativePhotoAllocationAccess.Send)
    case roles(RolesSend)
    var projection: InitialPhotoAllocationRequest.Projection {
        switch self { case .legacy: .legacy; case .roles: .roles }
    }
    enum Reply { case legacy(InitialPhotoAllocationReply), roles(InitialPhotoAllocationRoleReply) }
    @MainActor func send(_ request: InitialPhotoAllocationRequest,
                        validate: @escaping SharedMediaNativePhotoAllocationAccess.Validator,
                        settle: @escaping SharedMediaNativePhotoAllocationAccess.Validator) async throws -> Reply {
        switch self {
        case .legacy(let send): return .legacy(try await send(request, validate, settle))
        case .roles(let send): return .roles(try await send(request, validate, settle))
        }
    }
}
