import Foundation

/// Attempt eligibility is minted only at capture entry and never inferred from
/// the eventual number of staged items. All completions belong to one draft.
struct CaptureDraftSession {
    struct Operation: Hashable {
        let generation: UUID
        let id: UUID
    }
    private(set) var generation = UUID()
    private(set) var operations: Set<Operation> = []
    private(set) var automaticAttempt: Operation?
    enum Ownership: Equatable {
        case unowned
        case account(UUID)
    }
    private(set) var ownership: Ownership = .unowned
    var accountID: UUID? {
        if case .account(let id) = ownership { return id }
        return nil
    }

    /// Fresh captures made before Auth resolves have no account-owned inputs.
    /// They may bind once; an already-owned draft must never move to another user.
    mutating func bindAccount(_ candidate: UUID?) -> Bool {
        if let accountID { return accountID == candidate }
        if let candidate { ownership = .account(candidate) }
        return true
    }

    func allowsAccount(_ candidate: UUID?) -> Bool {
        accountID == nil || accountID == candidate
    }

    var hasUnresolvedWork: Bool { !operations.isEmpty }

    mutating func begin(autoSubmit: Bool, compositionIsEmpty: Bool, isRefining: Bool) -> Operation {
        let operation = Operation(generation: generation, id: UUID())
        if autoSubmit && compositionIsEmpty && !isRefining && operations.isEmpty {
            automaticAttempt = operation
        } else {
            automaticAttempt = nil
        }
        operations.insert(operation)
        return operation
    }

    mutating func beginRelatedWork() -> Operation {
        let operation = Operation(generation: generation, id: UUID())
        operations.insert(operation)
        return operation
    }

    func contains(_ operation: Operation) -> Bool {
        operation.generation == generation && operations.contains(operation)
    }

    @discardableResult
    mutating func finish(_ operation: Operation, succeeded: Bool) -> Bool {
        guard contains(operation) else { return false }
        operations.remove(operation)
        if !succeeded { revokeAutomaticSubmission() }
        return true
    }

    mutating func revokeAutomaticSubmission() { automaticAttempt = nil }
    mutating func reset() { self = CaptureDraftSession() }
}
