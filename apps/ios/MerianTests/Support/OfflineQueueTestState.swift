import SwiftData

@testable import Merian

/// Restore the fixture's context even when a case throws or has its own legacy
/// cleanup. Tests still own completion of every async operation they start;
/// this scope never cancels or drains app-host tasks on their behalf.
@MainActor
struct OfflineQueueTestState {
    private let context = OfflineQueueManager.shared.modelContext

    func restore() {
        OfflineQueueManager.shared.modelContext = context
    }

    static func withState(performing operation: @Sendable () async throws -> Void) async throws {
        let state = OfflineQueueTestState()
        defer { state.restore() }
        try await operation()
    }
}
