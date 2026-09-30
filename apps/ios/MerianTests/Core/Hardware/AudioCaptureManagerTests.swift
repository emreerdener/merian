import AVFoundation
import Foundation
import os
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

/// A synthetic microphone feeding the production stream/DSP and a real WAV.
private final class AudioCapturePCMProbe: Sendable {
    private struct State {
        var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
        var file: AVAudioFile?
        var isRunning = false
        var starts = 0
        var tapInstalls = 0
    }
    // The writer never escapes the lock; AVAudioFile is not Sendable on iOS 17.
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    var starts: Int { state.withLock { $0.starts } }
    var tapInstalls: Int { state.withLock { $0.tapInstalls } }

    func makeEngine(
        onStart: @escaping @Sendable () throws -> Void = {}
    ) -> AudioRecordingEngineController.Engine {
        .init(
            readInputFormat: { .init(sampleRate: 48_000, channelCount: 1) },
            reset: {},
            installTap: { [self] url, continuation in
                let format = try #require(AudioRecordingWAVFormatPolicy.makeFormat(
                    sampleRate: 48_000, channelCount: 1
                ))
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                state.withLock {
                    $0.file = file
                    $0.continuation = continuation
                    $0.tapInstalls += 1
                }
            },
            prepare: {},
            start: { [self] in
                state.withLock { $0.isRunning = true; $0.starts += 1 }
                try onStart()
            },
            pause: { [self] in state.withLock { $0.isRunning = false } },
            removeTap: { [self] in state.withLock { $0.file = nil; $0.continuation = nil } },
            stop: { [self] in state.withLock { $0.isRunning = false } }
        )
    }

    func emit(amplitude: Float) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        buffer.frameLength = 4096
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<4096 {
            samples[index] = amplitude * sin(Float(index) * 2 * .pi * 1000 / 48_000)
        }
        try state.withLock {
            guard $0.isRunning else { return }
            try $0.file?.write(from: buffer)
            $0.continuation?.yield(buffer)
        }
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

    @Test("Repeated pause/resume continues the graph, countdown, and same WAV")
    func pauseResumeContinuesPCMAndGraph() async throws {
        let probe = AudioCapturePCMProbe()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let manager = makePCMManager(probe: probe, url: url)
        defer { manager.reset(); try? FileManager.default.removeItem(at: url) }
        try await manager.startRecording()
        try probe.emit(amplitude: 0.2)
        try await waitUntil { manager.spectrogramColumns.count == 2 }
        let firstColumns = manager.spectrogramColumns

        for cycle in 1...3 {
            manager.pauseRecording()
            let progress = manager.recordingProgress
            let columns = manager.spectrogramColumns
            try probe.emit(amplitude: 0.9)
            try await Task.sleep(for: .milliseconds(180))
            #expect(manager.recordingProgress == progress)
            #expect(manager.spectrogramColumns == columns)

            manager.resumeRecording()
            manager.resumeRecording()
            try await waitUntil { !manager.debugHasResumeTask }
            #expect(!manager.isPaused)
            #expect(manager.isRecording)
            try probe.emit(amplitude: 0.2 + Float(cycle) * 0.1)
            try await waitUntil { manager.spectrogramColumns.count == (cycle + 1) * 2 }
            try await waitUntil { manager.recordingProgress > progress }
            #expect(Array(manager.spectrogramColumns.prefix(2)) == firstColumns)
        }
        #expect(probe.starts == 4)
        #expect(probe.tapInstalls == 1)
        manager.stopRecordingEarly()
        #expect(manager.audioFilePath == url.lastPathComponent)
        let columns = manager.spectrogramColumns
        try probe.emit(amplitude: 0.9)
        #expect(manager.spectrogramColumns == columns)
        let file = try AVAudioFile(forReading: url)
        #expect(file.length == 4 * 4096)
        let recorded = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4 * 4096))
        try file.read(into: recorded)
        let samples = try #require(recorded.floatChannelData?[0])
        for segment in 0..<4 {
            let peak = (segment * 4096..<(segment + 1) * 4096).map { abs(samples[$0]) }.max() ?? 0
            #expect(abs(peak - (0.2 + Float(segment) * 0.1)) < 0.01)
        }
    }

    @Test("Startup samples are retained and cancelled startup clears them", arguments: [false, true])
    func startupSamplesRespectCancellation(cancelStartup: Bool) async throws {
        let probe = AudioCapturePCMProbe()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        // Engine.start is synchronous on the detached setup worker. Keep its
        // return pending so DSP reaches the manager before startup completes.
        let startReturnGate = DispatchSemaphore(value: 0)
        let manager = makePCMManager(probe: probe, url: url, onStart: {
            try probe.emit(amplitude: 0.2)
            _ = startReturnGate.wait(timeout: .now() + 5)
        })
        defer {
            startReturnGate.signal()
            manager.reset()
            try? FileManager.default.removeItem(at: url)
        }
        let startup = Task { try await manager.startRecording() }
        try await waitUntil { manager.spectrogramColumns.count == 2 }
        #expect(!manager.isRecording)
        if cancelStartup { manager.cancelPendingRecordingTransition() }
        startReturnGate.signal()
        if cancelStartup {
            await #expect(throws: CancellationError.self) { try await startup.value }
            #expect(manager.spectrogramColumns.isEmpty)
            #expect(!manager.isRecording)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        } else {
            try await startup.value
            #expect(manager.isRecording)
            #expect(manager.spectrogramColumns.count == 2)
        }
    }

    private func makePCMManager(
        probe: AudioCapturePCMProbe,
        url: URL,
        onStart: @escaping @Sendable () throws -> Void = {}
    ) -> AudioCaptureManager {
        let coordinator = AudioSessionCoordinator(operations: .init(
            configureAndActivate: { _ in }, deactivate: {}
        ))
        return AudioCaptureManager(dependencies: .init(
            recording: .init(
                makeEngine: { probe.makeEngine(onStart: onStart) },
                activateSession: { rate in
                    try await coordinator.activate(.recordMeasurement(preferredSampleRate: rate))
                },
                deactivateSession: { await coordinator.deactivate(ifCurrent: $0) },
                waitForInputRouteRecovery: {},
                makeFileURL: { url },
                deleteFile: { try? FileManager.default.removeItem(at: $0) }
            ),
            hasMicrophonePermission: { true }
        ))
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
