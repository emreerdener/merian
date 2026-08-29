import Foundation

@MainActor
struct ScansGridInteractions {
    struct Dependencies {
        let triggerQueuedSelection: @MainActor () -> Void
        let triggerCompletedSelection: @MainActor () -> Void
        let triggerAddSelection: @MainActor () -> Void

        @MainActor
        static var live: Self {
            let haptics = AppDIContainer.shared.hapticManager
            return Self(
                triggerQueuedSelection: {
                    haptics.triggerMediumPulse()
                },
                triggerCompletedSelection: {
                    haptics.triggerSheetSpring()
                },
                triggerAddSelection: {
                    haptics.triggerSheetSpring()
                }
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func selectQueuedScan(
        _ snapshot: QueuedScanSnapshot,
        onSelect: ((QueuedScanSnapshot) -> Void)?
    ) {
        dependencies.triggerQueuedSelection()
        onSelect?(snapshot)
    }

    func selectCompletedScan(
        _ record: LocalScanRecord,
        onSelect: (LocalScanRecord) -> Void
    ) {
        dependencies.triggerCompletedSelection()
        onSelect(record)
    }

    func selectAddScans(onSelect: (() -> Void)?) {
        dependencies.triggerAddSelection()
        onSelect?()
    }
}
