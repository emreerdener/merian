@preconcurrency import AVFoundation
import Foundation
import os
import Testing
@testable import Merian

@MainActor
@Suite("Camera video audio ownership")
struct CameraVideoAudioSessionTests {
    private enum Failure: Error { case recording }

    private final class Probe: Sendable {
        let events = OSAllocatedUnfairLock(initialState: [String]())
        func append(_ event: String) { events.withLock { $0.append(event) } }
        var snapshot: [String] { events.withLock { $0 } }
    }

    private func fixture(_ probe: Probe) -> (CameraVideoAudioSession, AudioSessionCoordinator) {
        let coordinator = AudioSessionCoordinator(operations: .init(
            configureAndActivate: { configuration in
                probe.append(configuration == .videoRecording ? "video" : "playback")
            },
            deactivate: { probe.append("deactivate") }
        ))
        let owner = CameraVideoAudioSession(dependencies: .init(
            coordinator: coordinator,
            configureInput: { probe.append($0 ? "attach" : "detach") }
        ))
        return (owner, coordinator)
    }

    @Test func liveInputAdapterNeverDiscoversMicrophoneForSilentVideo() async throws {
        let probe = Probe()
        let owner = liveInputFixture(probe)
        try await owner.withAudio(includeAudio: false) { probe.append("record") }
        #expect(probe.snapshot == ["record"])
    }

    @Test func liveInputAdapterDiscoversMicrophoneOnlyAfterLeaseAndNeverDuringCleanup() async throws {
        let probe = Probe()
        let owner = liveInputFixture(probe)
        for _ in 0..<2 {
            await #expect(throws: Failure.self) {
                try await owner.withAudio(includeAudio: true) {
                    probe.append("record")
                    throw Failure.recording
                }
            }
        }
        #expect(probe.snapshot == [
            "activate", "microphone", "record", "deactivate",
            "activate", "microphone", "record", "deactivate"
        ])
    }

    private func liveInputFixture(_ probe: Probe) -> CameraVideoAudioSession {
        let session = AVCaptureSession()
        let queue = DispatchQueue(label: "CameraVideoAudioSessionTests.input")
        let coordinator = AudioSessionCoordinator(operations: .init(
            configureAndActivate: { _ in probe.append("activate") },
            deactivate: { probe.append("deactivate") }
        ))
        return CameraVideoAudioSession(dependencies: .init(
            coordinator: coordinator,
            configureInput: { includeAudio in
                await CameraVideoAudioSession.configureInput(
                    includeAudio, sessionProvider: { session }, queue: queue,
                    makeAudioInput: {
                        dispatchPrecondition(condition: .onQueue(queue))
                        probe.append("microphone")
                        return nil
                    }
                )
            }
        ))
    }

    private var priorityError: NSError {
        NSError(domain: NSOSStatusErrorDomain, code: AVAudioSession.ErrorCode.insufficientPriority.rawValue)
    }

    @Test func microphonePriorityConflictRecordsSilentlyAndNextAttemptCanUseAudio() async throws {
        let probe = Probe()
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let error = priorityError
        let coordinator = AudioSessionCoordinator(operations: .init(
            configureAndActivate: { _ in
                probe.append("activate")
                let attempt = attempts.withLock { $0 += 1; return $0 }
                if attempt == 1 { throw error }
            },
            deactivate: { probe.append("deactivate") }
        ))
        let owner = CameraVideoAudioSession(dependencies: .init(
            coordinator: coordinator,
            configureInput: { probe.append($0 ? "attach" : "detach") }
        ))
        for _ in 0..<2 {
            let result = try await owner.withAudio(includeAudio: true) {
                probe.append("record")
                return 42
            }
            #expect(result == 42)
        }
        #expect(probe.snapshot == [
            "detach", "activate", "deactivate", "record", "detach",
            "detach", "activate", "attach", "record", "detach", "deactivate"
        ])
    }

    @Test func silentPriorityFallbackPreservesRestoredPlaybackOwner() async throws {
        let probe = Probe()
        let error = priorityError
        let coordinator = AudioSessionCoordinator(operations: .init(
            configureAndActivate: { configuration in
                probe.append(configuration == .videoRecording ? "video" : "playback")
                if configuration == .videoRecording { throw error }
            },
            deactivate: { probe.append("deactivate") }
        ))
        let playback = try await coordinator.activate(.playback)
        let owner = CameraVideoAudioSession(dependencies: .init(
            coordinator: coordinator,
            configureInput: { probe.append($0 ? "attach" : "detach") }
        ))
        try await owner.withAudio(includeAudio: true) { probe.append("record") }
        #expect(await coordinator.isCurrent(playback))
        #expect(probe.snapshot == ["playback", "detach", "video", "playback", "record", "detach"])
    }

    @Test func otherActivationErrorsDoNotStartSilentRecording() async {
        let errors: [any Error] = [
            CancellationError(),
            NSError(domain: "Unrelated", code: priorityError.code),
            NSError(domain: NSOSStatusErrorDomain, code: AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue),
            NSError(domain: NSOSStatusErrorDomain, code: AVAudioSession.ErrorCode.mediaServicesFailed.rawValue)
        ]
        for error in errors {
            let probe = Probe()
            let coordinator = AudioSessionCoordinator(operations: .init(
                configureAndActivate: { _ in throw error },
                deactivate: { probe.append("deactivate") }
            ))
            let owner = CameraVideoAudioSession(dependencies: .init(
                coordinator: coordinator,
                configureInput: { probe.append($0 ? "attach" : "detach") }
            ))
            do {
                try await owner.withAudio(includeAudio: true) { probe.append("record") }
                Issue.record("Unexpected activation failure was swallowed")
            } catch {}
            #expect(probe.snapshot == ["detach", "deactivate", "detach"])
        }
    }

    @Test func cancellationDuringPriorityFailurePreventsSilentRecording() async {
        let probe = Probe()
        let error = priorityError
        let coordinator = AudioSessionCoordinator(operations: .init(
            configureAndActivate: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                throw error
            },
            deactivate: { probe.append("deactivate") }
        ))
        let owner = CameraVideoAudioSession(dependencies: .init(
            coordinator: coordinator,
            configureInput: { probe.append($0 ? "attach" : "detach") }
        ))
        let task = Task {
            try await owner.withAudio(includeAudio: true) { probe.append("record") }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(probe.snapshot == ["detach", "deactivate", "detach"])
    }

    @Test func priorityErrorFromMovieOperationIsNotRetriedOrSwallowed() async throws {
        let probe = Probe()
        let (owner, _) = fixture(probe)
        do {
            try await owner.withAudio(includeAudio: true) {
                probe.append("record")
                throw priorityError
            }
            Issue.record("Movie failure was swallowed")
        } catch {
            #expect((error as NSError).code == priorityError.code)
        }
        #expect(probe.snapshot == ["detach", "video", "attach", "record", "detach", "deactivate"])
    }

    @Test func delayedPlaybackCleanupCannotDeactivateVideo() async throws {
        let probe = Probe()
        let (owner, coordinator) = fixture(probe)
        let playback = try await coordinator.activate(.playback)

        let result = try await owner.withAudio(includeAudio: true) {
            await coordinator.deactivate(ifCurrent: playback)
            #expect(probe.snapshot == ["playback", "detach", "video", "attach"])
            return 42
        }

        #expect(result == 42)
        #expect(probe.snapshot == ["playback", "detach", "video", "attach", "detach", "deactivate"])
    }

    @Test func failureReleasesMicrophoneBeforeLeaseAndNextAttemptReactivates() async throws {
        let probe = Probe()
        let (owner, _) = fixture(probe)
        await #expect(throws: Failure.self) {
            try await owner.withAudio(includeAudio: true) { throw Failure.recording }
        }
        try await owner.withAudio(includeAudio: true) {}
        #expect(probe.snapshot == [
            "detach", "video", "attach", "detach", "deactivate",
            "detach", "video", "attach", "detach", "deactivate"
        ])
    }

    @Test func silentVideoDoesNotAcquireOrReleasePlaybackLease() async throws {
        let probe = Probe()
        let (owner, coordinator) = fixture(probe)
        let playback = try await coordinator.activate(.playback)
        try await owner.withAudio(includeAudio: false) {}
        #expect(await coordinator.isCurrent(playback))
        #expect(probe.snapshot == ["playback", "detach", "detach"])
    }

    @Test func videoCleanupCannotDeactivateReplacementPlayback() async throws {
        let probe = Probe()
        let (owner, coordinator) = fixture(probe)
        let playback = try await owner.withAudio(includeAudio: true) {
            try await coordinator.activate(.playback)
        }
        #expect(await coordinator.isCurrent(playback))
        #expect(!probe.snapshot.contains("deactivate"))
    }

    @Test func overlappingRequestCannotReconfigureActiveMovie() async throws {
        let probe = Probe()
        let (owner, _) = fixture(probe)
        try await owner.withAudio(includeAudio: true) {
            let before = probe.snapshot
            do {
                try await owner.withAudio(includeAudio: true) {
                    Issue.record("Overlapping recording was admitted")
                }
                Issue.record("Overlapping recording should throw")
            } catch {
                #expect((error as NSError).code == -7)
            }
            #expect(probe.snapshot == before)
        }
    }

    @Test func cancellationDuringInputPreparationCleansUpWithoutStartingMovie() async throws {
        let probe = Probe()
        let coordinator = AudioSessionCoordinator(operations: .init(
            configureAndActivate: { _ in probe.append("video") },
            deactivate: { probe.append("deactivate") }
        ))
        let owner = CameraVideoAudioSession(dependencies: .init(
            coordinator: coordinator,
            configureInput: { includeAudio in
                probe.append(includeAudio ? "attach" : "detach")
                if includeAudio { withUnsafeCurrentTask { $0?.cancel() } }
            }
        ))
        let task = Task {
            try await owner.withAudio(includeAudio: true) {
                Issue.record("A cancelled preparation started the movie")
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(probe.snapshot == ["detach", "video", "attach", "detach", "deactivate"])
    }
}
