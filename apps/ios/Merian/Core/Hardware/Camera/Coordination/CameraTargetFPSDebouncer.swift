import Foundation

/// Coalesces target-FPS changes while ensuring only the latest scheduled
/// application can read or publish a value.
///
/// Task cancellation is cooperative, so the UUID generation is the authority
/// for both applying and clearing state.
@MainActor
final class CameraTargetFPSDebouncer {
    typealias Sleeper = @Sendable (UInt64) async -> Void

    nonisolated static let defaultDelayNanoseconds: UInt64 = 100_000_000

    private let delayNanoseconds: UInt64
    private let sleep: Sleeper
    private var generationID: UUID?
    private var task: Task<Void, Never>?

    init(
        delayNanoseconds: UInt64 = CameraTargetFPSDebouncer.defaultDelayNanoseconds,
        sleep: @escaping Sleeper = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.sleep = sleep
    }

    @discardableResult
    func schedule(
        currentTargetFPS: @escaping @MainActor @Sendable () -> Int,
        apply: @escaping @MainActor @Sendable (Int) -> Void
    ) -> Task<Void, Never> {
        task?.cancel()

        let scheduledGenerationID = UUID()
        generationID = scheduledGenerationID
        let delayNanoseconds = delayNanoseconds
        let sleep = sleep

        let scheduledTask = Task { @MainActor [weak self] in
            await sleep(delayNanoseconds)

            guard let self,
                  !Task.isCancelled,
                  generationID == scheduledGenerationID else { return }

            // Read after the debounce window. A target mutation that happened
            // while the task slept must supersede the value that triggered it.
            let latestFPS = currentTargetFPS()

            guard !Task.isCancelled,
                  generationID == scheduledGenerationID else { return }

            apply(latestFPS)
            clear(generationID: scheduledGenerationID)
        }
        task = scheduledTask
        return scheduledTask
    }

    private func clear(generationID expectedGenerationID: UUID) {
        guard generationID == expectedGenerationID else { return }
        generationID = nil
        task = nil
    }
}
