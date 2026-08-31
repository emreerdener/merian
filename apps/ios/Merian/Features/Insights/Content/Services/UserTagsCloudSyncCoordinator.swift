import Foundation

@MainActor
final class UserTagsCloudSyncCoordinator {
    struct Request: Equatable, Sendable {
        let scanID: String
        let tags: [String]
        let expectedUserID: UUID
    }

    typealias Operation = @MainActor (_ request: Request) async -> Void

    private let operation: Operation
    private var tailTask: Task<Void, Never>?
    private var latestRequestGeneration: UInt64 = 0

    init(operation: @escaping Operation) {
        self.operation = operation
    }

    func enqueue(_ request: Request) {
        latestRequestGeneration &+= 1
        let requestGeneration = latestRequestGeneration
        let predecessor = tailTask
        let operation = operation

        tailTask = Task(priority: .background) { @MainActor [weak self] in
            _ = await predecessor?.value
            await operation(request)
            self?.clearTail(ifCurrent: requestGeneration)
        }
    }

    func waitForPendingWork() async {
        _ = await tailTask?.value
    }

    private func clearTail(ifCurrent requestGeneration: UInt64) {
        guard latestRequestGeneration == requestGeneration else { return }
        tailTask = nil
    }
}
