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
