import Foundation
import Observation

@MainActor
@Observable
final class LibraryRestorationState {
    enum Status: Equatable {
        case notStarted
        case restoring
        case needsAttention
        case complete
    }

    private(set) var accountID: UUID?
    private(set) var status: Status = .notStarted
    private var generation = UUID()

    func begin(accountID: UUID) -> UUID {
        generation = UUID()
        self.accountID = accountID
        status = .restoring
        return generation
    }

    func finish(generation: UUID, complete: Bool) {
        guard self.generation == generation else { return }
        status = complete ? .complete : .needsAttention
    }

    func reset() {
        generation = UUID()
        accountID = nil
        status = .notStarted
    }
}
