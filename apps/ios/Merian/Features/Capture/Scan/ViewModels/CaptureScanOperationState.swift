import Foundation

struct CaptureScanVideoGeneration: Equatable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@MainActor
final class CaptureScanOperationState {
    private var videoRecordingGeneration: CaptureScanVideoGeneration?
    private var videoRecordingTask: Task<Void, Never>?
    private var videoRecordingProgressTask: Task<Void, Never>?

    func beginVideoRecording() -> CaptureScanVideoGeneration {
        cancelVideoRecording()
        let generation = CaptureScanVideoGeneration()
        videoRecordingGeneration = generation
        return generation
    }

    @discardableResult
    func installVideoRecordingTask(
        _ task: Task<Void, Never>,
        for generation: CaptureScanVideoGeneration
    ) -> Bool {
        guard videoRecordingGeneration == generation else {
            task.cancel()
            return false
        }
        videoRecordingTask?.cancel()
        videoRecordingTask = task
        return true
    }

    func replaceVideoRecordingProgressTask(
        _ task: Task<Void, Never>,
        for generation: CaptureScanVideoGeneration
    ) {
        guard videoRecordingGeneration == generation else {
            task.cancel()
            return
        }
        videoRecordingProgressTask?.cancel()
        videoRecordingProgressTask = task
    }

    func isCurrent(_ generation: CaptureScanVideoGeneration) -> Bool {
        videoRecordingGeneration == generation
    }

    @discardableResult
    func finishVideoRecording(
        _ generation: CaptureScanVideoGeneration
    ) -> Bool {
        guard videoRecordingGeneration == generation else { return false }
        videoRecordingProgressTask?.cancel()
        videoRecordingProgressTask = nil
        videoRecordingTask = nil
        videoRecordingGeneration = nil
        return true
    }

    func cancelVideoRecording() {
        videoRecordingTask?.cancel()
        videoRecordingProgressTask?.cancel()
        videoRecordingTask = nil
        videoRecordingProgressTask = nil
        videoRecordingGeneration = nil
    }
}
