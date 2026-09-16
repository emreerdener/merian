import Foundation

struct GhostProfileMergePreparation: Equatable, Sendable {
    let handoffID: String
    let handoffSecret: String
    let expiresAt: String
}

/// Typed boundary for the provider-bound Ghost profile merge route and its
/// Supabase-specific error classifications. Auth admission, durable queue
/// mutation, provider synchronization, and task lifetime remain with focused
/// owners.
@MainActor
struct GhostProfileMergeRemoteService {
    typealias PrepareOperation = @MainActor (
        String,
        String
    ) async throws -> GhostProfileMergePreparation
    typealias CompleteOperation = @MainActor (
        PendingGhostProfileMerge
    ) async throws -> Void
    typealias RefreshIdentityOperation = @MainActor () async throws -> Void
    typealias ErrorClassifier = @MainActor (Error) -> Bool

    private let prepareOperation: PrepareOperation
    private let completeOperation: CompleteOperation
    private let refreshIdentityOperation: RefreshIdentityOperation
    private let providerConflictClassifier: ErrorClassifier
    private let terminalHandoffClassifier: ErrorClassifier

    init(
        prepare: @escaping PrepareOperation,
        complete: @escaping CompleteOperation,
        refreshIdentity: @escaping RefreshIdentityOperation,
        requiresProviderBoundMerge: @escaping ErrorClassifier,
        isTerminalHandoffError: @escaping ErrorClassifier
    ) {
        prepareOperation = prepare
        completeOperation = complete
        refreshIdentityOperation = refreshIdentity
        providerConflictClassifier = requiresProviderBoundMerge
        terminalHandoffClassifier = isTerminalHandoffError
    }

    func prepare(
        provider: String,
        providerSubject: String
    ) async throws -> GhostProfileMergePreparation {
        try await prepareOperation(provider, providerSubject)
    }

    func complete(_ handoff: PendingGhostProfileMerge) async throws {
        try await completeOperation(handoff)
    }

    func refreshIdentity() async throws {
        try await refreshIdentityOperation()
    }

    func requiresProviderBoundMerge(after error: Error) -> Bool {
        providerConflictClassifier(error)
    }

    func isTerminalHandoffError(_ error: Error) -> Bool {
        terminalHandoffClassifier(error)
    }
}
