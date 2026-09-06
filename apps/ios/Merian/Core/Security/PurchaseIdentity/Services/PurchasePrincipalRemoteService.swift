import Foundation

@MainActor
struct PurchasePrincipalRemoteService {
    struct ResolveRequest: Equatable {
        let installationCapability: String
        let bindingIntentGeneration: Int64
    }

    struct PrepareRequest: Equatable {
        let installationCapability: String
        let rotationId: UUID
        let rotationSecret: String
        let expectedBindingGeneration: Int64
    }

    struct ClaimRequest: Equatable {
        let installationCapability: String
        let rotationId: UUID
        let rotationSecret: String
    }

    struct CancelRequest: Equatable {
        let installationCapability: String
        let rotationId: UUID
        let rotationSecret: String
    }

    typealias ResolveOperation = @MainActor (
        ResolveRequest
    ) async throws -> PurchasePrincipalResolveResponse
    typealias PrepareOperation = @MainActor (
        PrepareRequest
    ) async throws -> PrincipalRotationPrepareResponse
    typealias ClaimOperation = @MainActor (
        ClaimRequest
    ) async throws -> PrincipalRotationClaimResponse
    typealias CancelOperation = @MainActor (
        CancelRequest
    ) async throws -> PrincipalRotationCancelResponse
    typealias UnsupportedRouteClassifier = @MainActor (Error) -> Bool

    private let resolveOperation: ResolveOperation
    private let prepareOperation: PrepareOperation
    private let claimOperation: ClaimOperation
    private let cancelOperation: CancelOperation
    private let unsupportedRouteClassifier: UnsupportedRouteClassifier

    init(
        resolve: @escaping ResolveOperation,
        prepare: @escaping PrepareOperation,
        claim: @escaping ClaimOperation,
        cancel: @escaping CancelOperation,
        isUnsupportedRoute: @escaping UnsupportedRouteClassifier
    ) {
        resolveOperation = resolve
        prepareOperation = prepare
        claimOperation = claim
        cancelOperation = cancel
        unsupportedRouteClassifier = isUnsupportedRoute
    }

    func resolve(
        _ request: ResolveRequest
    ) async throws -> PurchasePrincipalResolveResponse {
        try await resolveOperation(request)
    }

    func prepare(
        _ request: PrepareRequest
    ) async throws -> PrincipalRotationPrepareResponse {
        try await prepareOperation(request)
    }

    func claim(
        _ request: ClaimRequest
    ) async throws -> PrincipalRotationClaimResponse {
        try await claimOperation(request)
    }

    func cancel(
        _ request: CancelRequest
    ) async throws -> PrincipalRotationCancelResponse {
        try await cancelOperation(request)
    }

    func isUnsupportedRoute(_ error: Error) -> Bool {
        unsupportedRouteClassifier(error)
    }
}
