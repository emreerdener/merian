import Foundation

struct CaptureScanStillGeneration: Equatable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

struct CaptureScanVideoGeneration: Equatable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@MainActor
final class CaptureScanOperationState {
    private var stillCaptureGeneration: CaptureScanStillGeneration?
    private var stillCaptureTask: Task<Void, Never>?
    private var videoRecordingGeneration: CaptureScanVideoGeneration?
    private var videoRecordingTask: Task<Void, Never>?
    private var videoRecordingProgressTask: Task<Void, Never>?

    var hasActiveVideoCapture: Bool {
        videoRecordingGeneration != nil
    }

    func beginStillCapture() -> CaptureScanStillGeneration {
        cancelStillCapture()
        let generation = CaptureScanStillGeneration()
        stillCaptureGeneration = generation
        return generation
    }

    @discardableResult
    func installStillCaptureTask(
        _ task: Task<Void, Never>,
        for generation: CaptureScanStillGeneration
    ) -> Bool {
        guard stillCaptureGeneration == generation else {
            task.cancel()
            return false
        }
        stillCaptureTask?.cancel()
        stillCaptureTask = task
        return true
    }

    func isCurrent(_ generation: CaptureScanStillGeneration) -> Bool {
        stillCaptureGeneration == generation
    }

    @discardableResult
    func finishStillCapture(
        _ generation: CaptureScanStillGeneration
    ) -> Bool {
        guard stillCaptureGeneration == generation else { return false }
        stillCaptureTask = nil
        stillCaptureGeneration = nil
        return true
    }

    @discardableResult
    func cancelStillCapture() -> Bool {
        guard stillCaptureGeneration != nil else { return false }
        stillCaptureTask?.cancel()
        stillCaptureTask = nil
        stillCaptureGeneration = nil
        return true
    }

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

    @discardableResult
    func cancelVideoRecording() -> Bool {
        guard videoRecordingGeneration != nil else { return false }
        videoRecordingTask?.cancel()
        videoRecordingProgressTask?.cancel()
        videoRecordingTask = nil
        videoRecordingProgressTask = nil
        videoRecordingGeneration = nil
        return true
    }
}
