import XCTest

@testable import Merian

@MainActor
final class CaptureScanOperationStateTests: XCTestCase {
    func testReplacementCancelsPriorGenerationAndFencesItsCompletion() {
        let state = CaptureScanOperationState()
        let firstGeneration = state.beginVideoRecording()
        let firstTask = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        XCTAssertTrue(state.installVideoRecordingTask(
            firstTask,
            for: firstGeneration
        ))

        let secondGeneration = state.beginVideoRecording()
        let secondTask = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        XCTAssertTrue(state.installVideoRecordingTask(
            secondTask,
            for: secondGeneration
        ))

        XCTAssertTrue(firstTask.isCancelled)
        XCTAssertFalse(state.finishVideoRecording(firstGeneration))
        XCTAssertTrue(state.isCurrent(secondGeneration))
        XCTAssertTrue(state.finishVideoRecording(secondGeneration))

        secondTask.cancel()
    }

    func testStaleTaskInstallationCancelsTheTask() {
        let state = CaptureScanOperationState()
        let generation = state.beginVideoRecording()
        state.cancelVideoRecording()

        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
        }

        XCTAssertFalse(state.installVideoRecordingTask(
            task,
            for: generation
        ))
        XCTAssertTrue(task.isCancelled)
        XCTAssertFalse(state.isCurrent(generation))
    }

    func testProgressReplacementAndFinishCancelOwnedTasks() {
        let state = CaptureScanOperationState()
        let generation = state.beginVideoRecording()
        let firstProgressTask = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        let secondProgressTask = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
        }

        state.replaceVideoRecordingProgressTask(
            firstProgressTask,
            for: generation
        )
        state.replaceVideoRecordingProgressTask(
            secondProgressTask,
            for: generation
        )

        XCTAssertTrue(firstProgressTask.isCancelled)
        XCTAssertFalse(secondProgressTask.isCancelled)
        XCTAssertTrue(state.finishVideoRecording(generation))
        XCTAssertTrue(secondProgressTask.isCancelled)
    }
}
