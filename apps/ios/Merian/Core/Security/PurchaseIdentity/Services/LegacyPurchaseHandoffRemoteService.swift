import Foundation

struct LegacyPurchaseIdentityHandoffPreparation: Equatable, Sendable {
    let handoffID: String
    let handoffSecret: String
    let expiresAt: String
}

enum LegacyPurchaseHandoffRemoteError: Error {
    case invalidResponse
}

/// Typed compatibility-route boundary for an already-issued legacy sign-out
/// purchase proof. Auth-session admission, provider linking, and proof storage
/// remain with their focused owners.
@MainActor
struct LegacyPurchaseHandoffRemoteService {
    typealias PrepareOperation = @MainActor () async throws
        -> LegacyPurchaseIdentityHandoffPreparation
    typealias HandoffOperation = @MainActor (
        PendingSignOutPurchaseHandoff
    ) async throws -> Void
    typealias BindOperation = @MainActor (
        PendingSignOutPurchaseHandoff,
        String
    ) async throws -> Void
    typealias TerminalErrorClassifier = @MainActor (Error) -> Bool

    private let prepareOperation: PrepareOperation
    private let bindOperation: BindOperation
    private let completeOperation: HandoffOperation
    private let cancelOperation: HandoffOperation
    private let terminalErrorClassifier: TerminalErrorClassifier

    init(
        prepare: @escaping PrepareOperation,
        bind: @escaping BindOperation,
        complete: @escaping HandoffOperation,
        cancel: @escaping HandoffOperation,
        isTerminalProofError: @escaping TerminalErrorClassifier
    ) {
        prepareOperation = prepare
        bindOperation = bind
        completeOperation = complete
        cancelOperation = cancel
        terminalErrorClassifier = isTerminalProofError
    }

    func prepare() async throws -> LegacyPurchaseIdentityHandoffPreparation {
        try await prepareOperation()
    }

    func bind(
        _ handoff: PendingSignOutPurchaseHandoff,
        to destinationUserID: String
    ) async throws {
        try await bindOperation(handoff, destinationUserID)
    }

    func complete(
        _ handoff: PendingSignOutPurchaseHandoff
    ) async throws {
        try await completeOperation(handoff)
    }

    func cancel(
        _ handoff: PendingSignOutPurchaseHandoff
    ) async throws {
        try await cancelOperation(handoff)
    }

    func isTerminalProofError(_ error: Error) -> Bool {
        terminalErrorClassifier(error)
    }
}
