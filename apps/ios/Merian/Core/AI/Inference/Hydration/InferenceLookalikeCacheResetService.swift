import Foundation
import SwiftData

/// Isolates the process-wide legacy lookalike-cache compatibility reset from
/// inference presentation and historical projection.
struct InferenceLookalikeCacheResetService: Sendable {
    struct Dependencies: Sendable {
        let needsReset: @MainActor @Sendable () -> Bool
        let scheduleReset:
            @MainActor @Sendable (_ modelContainer: ModelContainer) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @MainActor
    var needsReset: Bool {
        dependencies.needsReset()
    }

    @MainActor
    func scheduleIfNeeded(in modelContainer: ModelContainer?) {
        guard dependencies.needsReset(), let modelContainer else { return }
        dependencies.scheduleReset(modelContainer)
    }
}
