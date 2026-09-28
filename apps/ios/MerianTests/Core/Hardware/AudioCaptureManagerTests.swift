import Foundation
import Testing

@testable import Merian

private actor AudioCaptureActivationGate {
    private var activationContinuation: CheckedContinuation<Void, Never>?
    private var activationCount = 0
    private var deactivationCount = 0

    func waitForActivationRelease() async {
        activationCount += 1
        await withCheckedContinuation { continuation in
            activationContinuation = continuation
        }
    }

    func releaseActivation() {
        activationContinuation?.resume()
        activationContinuation = nil
    }

    func counts() -> (activation: Int, deactivation: Int) {
        (activationCount, deactivationCount)
    }

    func recordDeactivation() {
        deactivationCount += 1
    }
}

private final class AudioEngineStartProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var startCount = 0

    func start() {
        lock.withLock {
            startCount += 1
        }
    }

    var startCallCount: Int {
        lock.withLock { startCount }
    }
}

@Suite("AudioCaptureManager")
@MainActor
struct AudioCaptureManagerTests {
    @Test("Fresh-install cleanup does not initialize microphone input")
    func freshInstallCleanupDoesNotInitializeMicrophoneInput() {
        let manager = AudioCaptureManager()

        #expect(!manager.debugHasAudioEngine)
        manager.reset()
        #expect(
            !manager.debugHasAudioEngine,
            "Lifecycle cleanup must not initialize AVAudioEngine input"
        )
    }

    @Test("Cancelled startup cleans pending recording resources")
    func cancelledStartupCleansPendingRecordingResources() async throws {
        let manager = AudioCaptureManager()
        let fileName = "\(UUID().uuidString).wav"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try Data("pending-audio".utf8).write(to: fileURL)

        manager.debugStageStartupState(
            fileName: fileName,
            dspTask: Task {
                try? await Task.sleep(for: .seconds(60))
            }
        )

        manager.debugHandleCancelledStartup()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(!manager.debugHasDSPTask)
        #expect(manager.debugPendingFileName == nil)
    }

    @Test("Early, paused, and maximum completion hand off once without review")
    func completionHandsOffWithoutReview() {
        for mode in ["early", "paused", "maximum"] {
            let manager = AudioCaptureManager()
            let fileName = "\(UUID().uuidString).wav"
            manager.debugStageRecordingForFinish(fileName: fileName, boostRecordingPreview: true)
            if mode == "paused" { manager.pauseRecording() }
            manager.debugFinishRecording(reachedMaxDuration: mode == "maximum")
            #expect(manager.audioFilePath == fileName)
            #expect(manager.pendingPlaybackPath == nil)
            #expect(manager.boostRecordingPreview)
            #expect(!manager.isRecording)
            #expect(!manager.isPaused)
            manager.stopRecordingEarly()
            #expect(manager.audioFilePath == fileName)
            manager.reset()
        }
    }

    @Test("Maximum duration feedback is emitted once even after duplicate completion")
    func maximumDurationFeedbackIsInjectedAndEmittedOnce() {
        var feedbackCount = 0
        let manager = AudioCaptureManager { feedbackCount += 1 }
        manager.debugStageRecordingForFinish(fileName: "maximum-duration.wav")
        manager.debugCompleteMaximumDurationRecording()
        manager.debugCompleteMaximumDurationRecording()
        #expect(feedbackCount == 1)
        #expect(manager.audioFilePath == "maximum-duration.wav")
        #expect(manager.pendingPlaybackPath == nil)
        manager.reset()
    }

    @Test("Acknowledgement retains the original; unclaimed completion cleanup deletes it")
    func completionOwnershipRequiresAcknowledgement() throws {
        for accept in [true, false] {
            let manager = AudioCaptureManager()
            let fileName = "\(UUID().uuidString).wav"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try Data([1, 2, 3]).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            manager.debugStageRecordingForFinish(fileName: fileName)
            manager.stopRecordingEarly()
            if accept { manager.acknowledgeStagedRecording() } else { manager.reset() }
            #expect(FileManager.default.fileExists(atPath: url.path) == accept)
            #expect(manager.audioFilePath == nil)
        }
    }

    @Test("A completed recording rejects a new start instead of silently succeeding")
    func unclaimedCompletionRejectsStart() async throws {
        let manager = AudioCaptureManager()
        manager.debugStageRecordingForFinish(fileName: "busy.wav")
        manager.stopRecordingEarly()
        defer { manager.reset() }
        do {
            try await manager.startRecording()
            Issue.record("Expected busy recording rejection")
        } catch AudioCaptureError.recordingBusy {
            #expect(manager.audioFilePath == "busy.wav")
        }
    }

    @Test("Duplicate resumes coalesce and cancellation fences late activation")
    func duplicateResumesCoalesceAndCancellationFencesActivation() async throws {
        let leaseCoordinator = AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { _ in },
                deactivate: {}
            )
        )
        let lease = try await leaseCoordinator.activate(.playback)
        let activationGate = AudioCaptureActivationGate()
        let engineStartProbe = AudioEngineStartProbe()
        let manager = AudioCaptureManager(
            dependencies: .init(
                activateRecordingSession: { _ in
                    await activationGate.waitForActivationRelease()
                    return lease
                },
                deactivateAudioSession: { _ in
                    await activationGate.recordDeactivation()
                },
                startEngine: { _ in
                    engineStartProbe.start()
                }
            )
        )
        manager.debugStagePausedRecording(progress: 0.4)

        manager.resumeRecording()
        manager.resumeRecording()
        try await waitUntil {
            await activationGate.counts().activation == 1
        }

        manager.cancelPendingRecordingTransition()
        await activationGate.releaseActivation()
        try await waitUntil { !manager.debugHasResumeTask }

        let counts = await activationGate.counts()
        #expect(counts.activation == 1)
        #expect(counts.deactivation == 1)
        #expect(engineStartProbe.startCallCount == 0)
        #expect(manager.isRecording)
        #expect(manager.isPaused)
        #expect(manager.recordingProgress == 0.4)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for audio transition state")
    }
}
