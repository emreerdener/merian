import AVFoundation
import Foundation
import Testing

@testable import Merian

private struct AudioRecordingEngineTestError: Error {}

private final class AudioRecordingEngineProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var remainingFormats: [AudioRecordingInputFormat]
    private var recordedEvents: [String] = []
    private let failsToStart: Bool

    init(
        formats: [AudioRecordingInputFormat] = [
            .init(sampleRate: 48_000, channelCount: 1)
        ],
        failsToStart: Bool = false
    ) {
        self.remainingFormats = formats
        self.failsToStart = failsToStart
    }

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    func recordLeaseDeactivation() {
        record("deactivateLease")
    }

    func makeEngine() -> AudioRecordingEngineController.Engine {
        .init(
            readInputFormat: { [self] in nextFormat() },
            reset: { [self] in record("reset") },
            installTap: { [self] _, _ in record("installTap") },
            prepare: { [self] in record("prepare") },
            start: { [self] in
                record("start")
                if failsToStart {
                    throw AudioRecordingEngineTestError()
                }
            },
            pause: { [self] in record("pause") },
            removeTap: { [self] in record("removeTap") },
            stop: { [self] in record("stop") }
        )
    }

    private func nextFormat() -> AudioRecordingInputFormat {
        lock.withLock {
            recordedEvents.append("readInputFormat")
            guard let format = remainingFormats.first else {
                return .init(sampleRate: 0, channelCount: 0)
            }
            if remainingFormats.count > 1 {
                remainingFormats.removeFirst()
            }
            return format
        }
    }

    private func record(_ event: String) {
        lock.withLock {
            recordedEvents.append(event)
        }
    }
}

private final class AudioRecordingFileProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var deletedURLs: [URL] = []

    var deletions: [URL] {
        lock.withLock { deletedURLs }
    }

    func recordDeletion(_ url: URL) {
        lock.withLock {
            deletedURLs.append(url)
        }
    }
}

private actor AudioRecordingAsyncProbe {
    private(set) var routeRecoveryWaitCount = 0
    private(set) var leaseDeactivationCount = 0

    func recordRouteRecoveryWait() {
        routeRecoveryWaitCount += 1
    }

    func recordDeactivation(
        _: AudioSessionCoordinator.Lease
    ) {
        leaseDeactivationCount += 1
    }
}

private actor AudioRecordingActivationGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int { waiters.count }

    func wait() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releaseFirst() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}

private final class AudioRecordingActivationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var attemptCount = 0

    func shouldFailAttempt() -> Bool {
        lock.withLock {
            attemptCount += 1
            return attemptCount == 1
        }
    }
}

@Suite("Audio recording engine controller")
@MainActor
struct AudioRecordingEngineControllerTests {
    @Test("Finish retains the WAV and tears down engine before its lease")
    func finishRetainsWAVAndTearsDownEngine() async throws {
        let engineProbe = AudioRecordingEngineProbe()
        let fileProbe = AudioRecordingFileProbe()
        let asyncProbe = AudioRecordingAsyncProbe()
        let coordinator = makeSessionCoordinator()
        let fileURL = temporaryAudioURL()
        let controller = makeController(
            engineProbe: engineProbe,
            fileProbe: fileProbe,
            asyncProbe: asyncProbe,
            coordinator: coordinator,
            fileURL: fileURL
        )

        let fileName = try await controller.start(
            preferredSampleRate: 48_000,
            onEvaluations: { _ in }
        )
        let finishedFileName = controller.finishRecording()
        try await waitUntil {
            await asyncProbe.leaseDeactivationCount == 1
        }

        #expect(fileName == fileURL.lastPathComponent)
        #expect(finishedFileName == fileURL.lastPathComponent)
        #expect(fileProbe.deletions.isEmpty)
        #expect(
            engineProbe.events == [
                "readInputFormat",
                "installTap",
                "prepare",
                "start",
                "removeTap",
                "stop",
                "deactivateLease"
            ]
        )
    }

    @Test("Failed engine start removes its tap and partial WAV")
    func failedStartRemovesTapAndPartialWAV() async throws {
        let engineProbe = AudioRecordingEngineProbe(failsToStart: true)
        let fileProbe = AudioRecordingFileProbe()
        let asyncProbe = AudioRecordingAsyncProbe()
        let coordinator = makeSessionCoordinator()
        let fileURL = temporaryAudioURL()
        let controller = makeController(
            engineProbe: engineProbe,
            fileProbe: fileProbe,
            asyncProbe: asyncProbe,
            coordinator: coordinator,
            fileURL: fileURL
        )

        await #expect(throws: AudioRecordingEngineTestError.self) {
            _ = try await controller.start(
                preferredSampleRate: nil,
                onEvaluations: { _ in }
            )
        }
        try await waitUntil {
            await asyncProbe.leaseDeactivationCount == 1
        }

        #expect(fileProbe.deletions == [fileURL])
        #expect(
            engineProbe.events == [
                "readInputFormat",
                "installTap",
                "prepare",
                "start",
                "removeTap",
                "stop",
                "deactivateLease"
            ]
        )
    }

    @Test("Input format recovery retries until hardware becomes usable")
    func inputFormatRecoverySucceeds() async throws {
        let engineProbe = AudioRecordingEngineProbe(
            formats: [
                .init(sampleRate: 0, channelCount: 0),
                .init(sampleRate: 0, channelCount: 0),
                .init(sampleRate: 44_100, channelCount: 1)
            ]
        )
        let fileProbe = AudioRecordingFileProbe()
        let asyncProbe = AudioRecordingAsyncProbe()
        let coordinator = makeSessionCoordinator()
        let controller = makeController(
            engineProbe: engineProbe,
            fileProbe: fileProbe,
            asyncProbe: asyncProbe,
            coordinator: coordinator,
            fileURL: temporaryAudioURL()
        )

        _ = try await controller.start(
            preferredSampleRate: nil,
            onEvaluations: { _ in }
        )
        _ = controller.finishRecording()

        #expect(await asyncProbe.routeRecoveryWaitCount == 2)
        #expect(
            engineProbe.events.prefix(7) == [
                "readInputFormat",
                "reset",
                "readInputFormat",
                "reset",
                "readInputFormat",
                "installTap",
                "prepare"
            ]
        )
    }

    @Test("Exhausted input recovery fails closed and deletes the WAV")
    func exhaustedInputRecoveryFailsClosed() async throws {
        let engineProbe = AudioRecordingEngineProbe(
            formats: [.init(sampleRate: 0, channelCount: 0)]
        )
        let fileProbe = AudioRecordingFileProbe()
        let asyncProbe = AudioRecordingAsyncProbe()
        let coordinator = makeSessionCoordinator()
        let fileURL = temporaryAudioURL()
        let controller = makeController(
            engineProbe: engineProbe,
            fileProbe: fileProbe,
            asyncProbe: asyncProbe,
            coordinator: coordinator,
            fileURL: fileURL
        )

        await #expect(throws: AudioCaptureError.self) {
            _ = try await controller.start(
                preferredSampleRate: nil,
                onEvaluations: { _ in }
            )
        }
        try await waitUntil {
            await asyncProbe.leaseDeactivationCount == 1
        }

        #expect(await asyncProbe.routeRecoveryWaitCount == 4)
        #expect(
            engineProbe.events.filter { $0 == "readInputFormat" }.count == 5
        )
        #expect(engineProbe.events.filter { $0 == "reset" }.count == 4)
        #expect(!engineProbe.events.contains("installTap"))
        #expect(!engineProbe.events.contains("start"))
        #expect(fileProbe.deletions == [fileURL])
    }

    @Test("Cancellation rejects a late activation lease and engine start")
    func cancellationRejectsLateActivationLease() async throws {
        let engineProbe = AudioRecordingEngineProbe()
        let fileProbe = AudioRecordingFileProbe()
        let asyncProbe = AudioRecordingAsyncProbe()
        let activationGate = AudioRecordingActivationGate()
        let coordinator = makeSessionCoordinator()
        let lease = try await coordinator.activate(
            .recordMeasurement(preferredSampleRate: nil)
        )
        let fileURL = temporaryAudioURL()
        let controller = AudioRecordingEngineController(
            dependencies: .init(
                makeEngine: { engineProbe.makeEngine() },
                activateSession: { _ in
                    await activationGate.wait()
                    return lease
                },
                deactivateSession: { returnedLease in
                    engineProbe.recordLeaseDeactivation()
                    await asyncProbe.recordDeactivation(returnedLease)
                    await coordinator.deactivate(ifCurrent: returnedLease)
                },
                waitForInputRouteRecovery: {
                    await asyncProbe.recordRouteRecoveryWait()
                },
                makeFileURL: { fileURL },
                deleteFile: { fileProbe.recordDeletion($0) }
            )
        )

        let startTask = Task {
            try await controller.start(
                preferredSampleRate: nil,
                onEvaluations: { _ in }
            )
        }
        try await waitUntil {
            await activationGate.waiterCount == 1
        }

        #expect(controller.cancelRecording() == nil)
        await activationGate.releaseFirst()
        await #expect(throws: CancellationError.self) {
            _ = try await startTask.value
        }
        try await waitUntil {
            await asyncProbe.leaseDeactivationCount == 1
        }

        #expect(
            engineProbe.events == [
                "deactivateLease",
                "removeTap",
                "stop"
            ]
        )
        #expect(fileProbe.deletions == [fileURL])
    }

    @Test("Concurrent resume requests coalesce at the controller boundary")
    func concurrentResumeRequestsCoalesce() async throws {
        let engineProbe = AudioRecordingEngineProbe()
        let fileProbe = AudioRecordingFileProbe()
        let asyncProbe = AudioRecordingAsyncProbe()
        let activationGate = AudioRecordingActivationGate()
        let coordinator = makeSessionCoordinator()
        let lease = try await coordinator.activate(
            .recordMeasurement(preferredSampleRate: nil)
        )
        let fileURL = temporaryAudioURL()
        let controller = AudioRecordingEngineController(
            dependencies: .init(
                makeEngine: { engineProbe.makeEngine() },
                activateSession: { _ in
                    await activationGate.wait()
                    return lease
                },
                deactivateSession: { returnedLease in
                    engineProbe.recordLeaseDeactivation()
                    await asyncProbe.recordDeactivation(returnedLease)
                    await coordinator.deactivate(ifCurrent: returnedLease)
                },
                waitForInputRouteRecovery: {},
                makeFileURL: { fileURL },
                deleteFile: { fileProbe.recordDeletion($0) }
            )
        )
        controller.debugStagePausedRecording()

        let firstResume = Task {
            try await controller.resume(preferredSampleRate: nil)
        }
        try await waitUntil {
            await activationGate.waiterCount == 1
        }

        await #expect(throws: CancellationError.self) {
            try await controller.resume(preferredSampleRate: nil)
        }
        #expect(await activationGate.waiterCount == 1)

        controller.invalidatePendingOperation()
        await activationGate.releaseFirst()
        await #expect(throws: CancellationError.self) {
            try await firstResume.value
        }
        try await waitUntil {
            await asyncProbe.leaseDeactivationCount == 1
        }
        _ = controller.cancelRecording()

        #expect(!engineProbe.events.contains("start"))
        #expect(fileProbe.deletions == [fileURL])
    }

    @Test("Failed resume activation does not poison a later retry")
    func failedResumeActivationAllowsRetry() async throws {
        let engineProbe = AudioRecordingEngineProbe()
        let fileProbe = AudioRecordingFileProbe()
        let asyncProbe = AudioRecordingAsyncProbe()
        let activationProbe = AudioRecordingActivationProbe()
        let coordinator = makeSessionCoordinator()
        let fileURL = temporaryAudioURL()
        let controller = AudioRecordingEngineController(
            dependencies: .init(
                makeEngine: { engineProbe.makeEngine() },
                activateSession: { preferredSampleRate in
                    if activationProbe.shouldFailAttempt() {
                        throw AudioRecordingEngineTestError()
                    }
                    return try await coordinator.activate(
                        .recordMeasurement(
                            preferredSampleRate: preferredSampleRate
                        )
                    )
                },
                deactivateSession: { lease in
                    engineProbe.recordLeaseDeactivation()
                    await asyncProbe.recordDeactivation(lease)
                    await coordinator.deactivate(ifCurrent: lease)
                },
                waitForInputRouteRecovery: {},
                makeFileURL: { fileURL },
                deleteFile: { fileProbe.recordDeletion($0) }
            )
        )
        controller.debugStagePausedRecording()

        await #expect(throws: AudioRecordingEngineTestError.self) {
            try await controller.resume(preferredSampleRate: nil)
        }
        try await controller.resume(preferredSampleRate: nil)
        _ = controller.cancelRecording()
        try await waitUntil {
            await asyncProbe.leaseDeactivationCount == 1
        }

        #expect(
            engineProbe.events == [
                "start",
                "removeTap",
                "stop",
                "deactivateLease"
            ]
        )
        #expect(fileProbe.deletions == [fileURL])
    }

    private func makeController(
        engineProbe: AudioRecordingEngineProbe,
        fileProbe: AudioRecordingFileProbe,
        asyncProbe: AudioRecordingAsyncProbe,
        coordinator: AudioSessionCoordinator,
        fileURL: URL
    ) -> AudioRecordingEngineController {
        AudioRecordingEngineController(
            dependencies: .init(
                makeEngine: { engineProbe.makeEngine() },
                activateSession: { preferredSampleRate in
                    try await coordinator.activate(
                        .recordMeasurement(
                            preferredSampleRate: preferredSampleRate
                        )
                    )
                },
                deactivateSession: { lease in
                    engineProbe.recordLeaseDeactivation()
                    await asyncProbe.recordDeactivation(lease)
                    await coordinator.deactivate(ifCurrent: lease)
                },
                waitForInputRouteRecovery: {
                    await asyncProbe.recordRouteRecoveryWait()
                },
                makeFileURL: { fileURL },
                deleteFile: { fileProbe.recordDeletion($0) }
            )
        )
    }

    private func makeSessionCoordinator() -> AudioSessionCoordinator {
        AudioSessionCoordinator(
            operations: .init(
                configureAndActivate: { _ in },
                deactivate: {}
            )
        )
    }

    private func temporaryAudioURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for asynchronous audio state")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

@Suite("Audio recording WAV format policy")
struct AudioRecordingWAVFormatPolicyTests {
    @Test("WAV output is canonical interleaved signed 16-bit PCM")
    func wavOutputUsesCanonicalPCMFormat() throws {
        let format = try #require(
            AudioRecordingWAVFormatPolicy.makeFormat(
                sampleRate: 44_100,
                channelCount: 2
            )
        )
        let formatID = try #require(
            format.settings[AVFormatIDKey] as? NSNumber
        )
        let bitDepth = try #require(
            format.settings[AVLinearPCMBitDepthKey] as? NSNumber
        )
        let isFloat = try #require(
            format.settings[AVLinearPCMIsFloatKey] as? NSNumber
        )
        let isNonInterleaved = try #require(
            format.settings[AVLinearPCMIsNonInterleaved] as? NSNumber
        )

        #expect(format.commonFormat == .pcmFormatInt16)
        #expect(format.sampleRate == 44_100)
        #expect(format.channelCount == 2)
        #expect(format.isInterleaved)
        #expect(formatID.uint32Value == kAudioFormatLinearPCM)
        #expect(bitDepth.intValue == 16)
        #expect(!isFloat.boolValue)
        #expect(!isNonInterleaved.boolValue)
    }

    @Test("Invalid hardware formats cannot produce a WAV format")
    func invalidHardwareFormatIsRejected() {
        #expect(
            AudioRecordingWAVFormatPolicy.makeFormat(
                sampleRate: 0,
                channelCount: 1
            ) == nil
        )
        #expect(
            AudioRecordingWAVFormatPolicy.makeFormat(
                sampleRate: 48_000,
                channelCount: 0
            ) == nil
        )
    }
}
