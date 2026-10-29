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
