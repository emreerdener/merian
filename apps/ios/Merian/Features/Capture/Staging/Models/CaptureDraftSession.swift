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
