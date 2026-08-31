import Foundation

@MainActor
final class FieldChatOperationState {
    struct SubjectActivation {
        let generation: UInt64
        let changed: Bool
    }

    private var subjectId: String?
    private var subjectGeneration: UInt64 = 0
    private var didLoadCurrentSubject = false
    private var loadRequestGeneration: UInt64 = 0
    private var promptRequestGeneration: UInt64 = 0

    private var preparationGeneration: UInt64 = 0
    private var preparationSubjectId: String?
    private var preparationTask: Task<Bool, Never>?

    var isPreparing: Bool {
        preparationTask != nil
    }

    var hasLoadedCurrentSubject: Bool {
        didLoadCurrentSubject
    }

    func prepare(
        subjectId: String,
        operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if preparationSubjectId?.caseInsensitiveCompare(subjectId) == .orderedSame,
           let preparationTask {
            let generation = preparationGeneration
            let canPresent = await preparationTask.value
            return canPresent &&
                !preparationTask.isCancelled &&
                !Task.isCancelled &&
                preparationGeneration == generation
        }

        cancelPreparation()

        preparationGeneration &+= 1
        let generation = preparationGeneration
        preparationSubjectId = subjectId
        let task = Task { @MainActor in
            await operation()
        }
        preparationTask = task

        let canPresent = await task.value
        guard preparationGeneration == generation,
              preparationSubjectId?.caseInsensitiveCompare(subjectId) == .orderedSame else {
            return false
        }
        preparationTask = nil
        preparationSubjectId = nil
        return canPresent && !task.isCancelled && !Task.isCancelled
    }

    func isCurrentPreparation(subjectId: String) -> Bool {
        preparationSubjectId?.caseInsensitiveCompare(subjectId) == .orderedSame
    }

    func activateSubject(_ newSubjectId: String) -> SubjectActivation {
        guard subjectId?.caseInsensitiveCompare(newSubjectId) != .orderedSame else {
            cancelPreparation(unlessPreparing: newSubjectId)
            return SubjectActivation(generation: subjectGeneration, changed: false)
        }

        cancelPreparation(unlessPreparing: newSubjectId)
        subjectGeneration &+= 1
        loadRequestGeneration &+= 1
        promptRequestGeneration &+= 1
        didLoadCurrentSubject = false
        subjectId = newSubjectId
        return SubjectActivation(generation: subjectGeneration, changed: true)
    }

    func clearSubject() {
        cancelPreparation()
        subjectGeneration &+= 1
        loadRequestGeneration &+= 1
        promptRequestGeneration &+= 1
        didLoadCurrentSubject = false
        subjectId = nil
    }

    func markCurrentSubjectLoaded() {
        didLoadCurrentSubject = true
    }

    func currentSubjectGeneration(for candidateId: String) -> UInt64? {
        isCurrentSubjectId(candidateId) ? subjectGeneration : nil
    }

    func isCurrentSubject(id candidateId: String, generation: UInt64) -> Bool {
        generation == subjectGeneration && isCurrentSubjectId(candidateId)
    }

    func beginLoadRequest() -> UInt64 {
        loadRequestGeneration &+= 1
        return loadRequestGeneration
    }

    func isCurrentLoadRequest(_ generation: UInt64) -> Bool {
        generation == loadRequestGeneration
    }

    func beginPromptRequest() -> UInt64 {
        promptRequestGeneration &+= 1
        return promptRequestGeneration
    }

    func isCurrentPromptRequest(_ generation: UInt64) -> Bool {
        generation == promptRequestGeneration
    }

    private func cancelPreparation(unlessPreparing preservedSubjectId: String? = nil) {
        guard let preparationTask else { return }
        if let preservedSubjectId,
           preparationSubjectId?
            .caseInsensitiveCompare(preservedSubjectId) == .orderedSame {
            return
        }

        preparationGeneration &+= 1
        preparationTask.cancel()
        self.preparationTask = nil
        preparationSubjectId = nil
    }

    private func isCurrentSubjectId(_ candidateId: String) -> Bool {
        subjectId?.caseInsensitiveCompare(candidateId) == .orderedSame
    }
}
