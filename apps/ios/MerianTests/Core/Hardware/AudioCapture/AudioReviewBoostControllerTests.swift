import Foundation
import Testing

@testable import Merian

@MainActor
private final class ReviewBoostPreparationProbe {
    var requests: [URL] = []
    var waiters: [CheckedContinuation<AudioBoostResult, Error>] = []

    func prepare(_ source: URL) async throws -> AudioBoostResult {
        requests.append(source)
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    func succeed(_ url: URL) { waiters.removeFirst().resume(returning: .init(url: url, gainDecibels: 12)) }
    func fail() { waiters.removeFirst().resume(throwing: CocoaError(.fileReadCorruptFile)) }

    var dependencies: AudioReviewBoostController.Dependencies {
        .init(
            prepare: { try await self.prepare($0) },
            remove: { try? FileManager.default.removeItem(at: $0) }
        )
    }
}

@MainActor
private final class ReviewBoostPlayer: AudioReviewPlaybackPlayer {
    let duration: TimeInterval = 10
    var currentTime: TimeInterval = 0
    var playCount = 0
    var stopCount = 0
    func play() -> Bool { playCount += 1; return true }
    func stop() { stopCount += 1 }
}

@MainActor
private final class ReviewBoostPlayerFactory {
    var urls: [URL] = []
    var players: [ReviewBoostPlayer] = []
    var failingURLs: Set<URL> = []

    func makePlayer(_ url: URL) throws -> ReviewBoostPlayer {
        if failingURLs.contains(url) { throw CocoaError(.fileReadCorruptFile) }
        urls.append(url)
        let player = ReviewBoostPlayer()
        players.append(player)
        return player
    }
}

@MainActor
private struct ReviewBoostFixture {
    let original: URL
    let boosted: URL
    let probe = ReviewBoostPreparationProbe()
    let factory = ReviewBoostPlayerFactory()

    init() throws {
        let token = UUID().uuidString
        original = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(token).wav")
        boosted = FileManager.default.temporaryDirectory.appendingPathComponent("review-\(token).caf")
        try Data([1, 2, 3, 4]).write(to: original)
        try Data([5, 6, 7, 8]).write(to: boosted)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: original)
        try? FileManager.default.removeItem(at: boosted)
    }

    func manager(enabled: Bool = false, autoSubmit: Bool = false) -> AudioCaptureManager {
        let session = AudioSessionCoordinator(operations: .init(configureAndActivate: { _ in }, deactivate: {}))
        let manager = AudioCaptureManager(dependencies: .init(
            activateRecordingSession: { _ in try await session.activate(.playback) },
            deactivateAudioSession: { await session.deactivate(ifCurrent: $0) },
            startEngine: { _ in },
            playback: .init(
                makePlayer: { try factory.makePlayer($0) },
                activateSession: { try await session.activate(.playback) },
                deactivateSession: { await session.deactivate(ifCurrent: $0) },
                waitForProgressTick: { try await Task.sleep(for: .seconds(60)) },
                waitForCompletion: { _ in try await Task.sleep(for: .seconds(60)) }
            ),
            reviewBoost: probe.dependencies
        ))
        manager.debugStageRecordingForFinish(
            fileName: original.lastPathComponent,
            autoSubmitOnMaxDuration: autoSubmit,
            boostRecordingPreview: enabled
        )
        manager.debugFinishRecording(reachedMaxDuration: autoSubmit)
        return manager
    }
}

@Suite("Recording preview boost")
@MainActor
struct AudioReviewBoostControllerTests {
    @Test("Preference defers work and duplicate requests coalesce")
    func deferredPreferenceCoalescesPreparation() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let owner = AudioReviewBoostController(dependencies: fixture.probe.dependencies)
        owner.configure(sourceURL: fixture.original, enabled: true)
        #expect(owner.state.isEnabled)
        #expect(fixture.probe.requests.isEmpty)
        var completions = 0
        #expect(owner.prepareIfNeeded { completions += 1 })
        #expect(owner.prepareIfNeeded { completions += 10 })
        try await waitUntil { fixture.probe.waiters.count == 1 }
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { owner.state.isReady }
        #expect(completions == 1)
        #expect(fixture.probe.requests == [fixture.original])
        #expect(owner.playbackURL == fixture.boosted)
        owner.reset()
        #expect(!FileManager.default.fileExists(atPath: fixture.boosted.path))
        #expect(try Data(contentsOf: fixture.original) == Data([1, 2, 3, 4]))
    }

    @Test("Disable rejects a cancellation-ignoring late result and allows a fresh request")
    func disableRejectsLateResult() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let owner = AudioReviewBoostController(dependencies: fixture.probe.dependencies)
        owner.configure(sourceURL: fixture.original, enabled: true)
        var completions = 0
        owner.prepareIfNeeded { completions += 1 }
        try await waitUntil { fixture.probe.waiters.count == 1 }
        owner.toggle()
        owner.toggle()
        owner.prepareIfNeeded { completions += 1 }
        try await waitUntil { fixture.probe.waiters.count == 2 }
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { !FileManager.default.fileExists(atPath: fixture.boosted.path) }
        #expect(owner.state.isPreparing)
        #expect(owner.playbackURL == nil)
        #expect(completions == 0)
        fixture.probe.fail()
        try await waitUntil { owner.state.hasFailed }
        #expect(completions == 1)
        owner.reset()
    }

    @Test("Replacement recording cannot adopt an old result")
    func replacementRejectsOldResult() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let owner = AudioReviewBoostController(dependencies: fixture.probe.dependencies)
        owner.configure(sourceURL: fixture.original, enabled: true)
        var completions = 0
        owner.prepareIfNeeded { completions += 1 }
        try await waitUntil { fixture.probe.waiters.count == 1 }
        owner.configure(sourceURL: fixture.original, enabled: false)
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { !FileManager.default.fileExists(atPath: fixture.boosted.path) }
        #expect(owner.state == AudioReviewBoostState())
        #expect(completions == 0)
    }

    @Test("Failure falls back and an explicit retry can succeed")
    func failureAllowsRetry() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let owner = AudioReviewBoostController(dependencies: fixture.probe.dependencies)
        owner.configure(sourceURL: fixture.original, enabled: true)
        owner.prepareIfNeeded {}
        try await waitUntil { fixture.probe.waiters.count == 1 }
        fixture.probe.fail()
        try await waitUntil { owner.state.hasFailed }
        #expect(!owner.state.isEnabled)
        #expect(!owner.state.isPreparing)
        owner.toggle()
        owner.prepareIfNeeded {}
        try await waitUntil { fixture.probe.waiters.count == 1 }
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { owner.state.isReady }
        #expect(!owner.state.hasFailed)
        owner.reset()
    }

    @Test("Manual boost is silent and playing source switches preserve the live position")
    func manualBoostAndSourceSwitching() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager()
        defer { manager.reset() }
        manager.seekPlayback(to: 0.25)
        manager.toggleReviewAudioBoost()
        try await waitUntil { fixture.probe.waiters.count == 1 }
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { manager.reviewBoostState.isReady }
        #expect(!manager.isPlaying)
        #expect(fixture.factory.players.isEmpty)
        #expect(manager.playbackProgress == 0.25)
        manager.playPendingRecording()
        try await waitUntil { fixture.factory.players.first?.playCount == 1 }
        let first = try #require(fixture.factory.players.first)
        #expect(first.currentTime == 2.5)
        first.currentTime = 4.2
        manager.toggleReviewAudioBoost()
        try await waitUntil { fixture.factory.players.last?.playCount == 1 && fixture.factory.players.count == 2 }
        #expect(fixture.factory.urls == [fixture.boosted, fixture.original])
        #expect(fixture.factory.players[1].currentTime == 4.2)
        #expect(first.stopCount == 1)
        #expect(manager.isPlaying)
        manager.stopPlayback()
        manager.seekPlayback(to: 0.6)
        manager.toggleReviewAudioBoost()
        #expect(fixture.factory.players.count == 2)
        #expect(!manager.isPlaying)
        #expect(manager.playbackProgress == 0.6)
        manager.playPendingRecording()
        try await waitUntil { fixture.factory.players.count == 3 && fixture.factory.players[2].playCount == 1 }
        #expect(fixture.factory.players[2].currentTime == 6)
    }

    @Test("Stop cancels pending automatic playback without clearing the preference")
    func stopRejectsPendingPlayback() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(enabled: true)
        defer { manager.reset() }
        #expect(fixture.probe.requests.isEmpty)
        manager.playPendingRecording()
        try await waitUntil { fixture.probe.waiters.count == 1 }
        #expect(manager.isPlaying)
        manager.stopPlayback()
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { !FileManager.default.fileExists(atPath: fixture.boosted.path) }
        #expect(fixture.factory.players.isEmpty)
        #expect(!manager.isPlaying)
        #expect(manager.reviewBoostState.isEnabled)
    }

    @Test("Submission uses unchanged original bytes and rejects late preparation")
    func submissionPreservesOriginalAndRecovery() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(enabled: true)
        defer { manager.reset() }
        manager.playPendingRecording()
        try await waitUntil { fixture.probe.waiters.count == 1 }
        manager.confirmAndSubmit()
        #expect(manager.audioFilePath == fixture.original.lastPathComponent)
        #expect(manager.pendingPlaybackPath == nil)
        #expect(try Data(contentsOf: fixture.original) == Data([1, 2, 3, 4]))
        manager.restoreSubmissionForReview()
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { !FileManager.default.fileExists(atPath: fixture.boosted.path) }
        #expect(manager.pendingPlaybackPath == fixture.original.lastPathComponent)
        #expect(manager.audioFilePath == nil)
        #expect(manager.reviewBoostState.isEnabled)
        #expect(!manager.reviewBoostState.isReady)
        #expect(!manager.isPlaying)
        #expect(fixture.factory.players.isEmpty)
    }

    @Test("Discard removes the original and any late derivative")
    func discardCleansLateDerivative() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager()
        manager.toggleReviewAudioBoost()
        try await waitUntil { fixture.probe.waiters.count == 1 }
        manager.discardPending()
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { !FileManager.default.fileExists(atPath: fixture.boosted.path) }
        #expect(!FileManager.default.fileExists(atPath: fixture.original.path))
        #expect(manager.reviewBoostState == AudioReviewBoostState())
        #expect(manager.pendingPlaybackPath == nil)
    }

    @Test("An unreadable derived source is removed and explicit retry prepares again")
    func rejectedDerivativeCanBePreparedAgain() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(enabled: true)
        defer { manager.reset() }
        fixture.factory.failingURLs = [fixture.boosted]
        manager.playPendingRecording()
        try await waitUntil { fixture.probe.waiters.count == 1 }
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { manager.reviewBoostState.hasFailed }
        #expect(manager.isPlaying)
        #expect(fixture.factory.urls == [fixture.original])
        #expect(!manager.reviewBoostState.isReady)
        #expect(!FileManager.default.fileExists(atPath: fixture.boosted.path))
        manager.toggleReviewAudioBoost()
        try await waitUntil { fixture.probe.requests.count == 2 }
        fixture.probe.fail()
        try await waitUntil { manager.reviewBoostState.hasFailed }
    }

    @Test("Unrecoverable original-source replacement stops the prior boosted player")
    func failedOriginalReplacementStopsPlayback() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(enabled: true)
        defer { manager.reset() }
        manager.playPendingRecording()
        try await waitUntil { fixture.probe.waiters.count == 1 }
        fixture.probe.succeed(fixture.boosted)
        try await waitUntil { fixture.factory.players.first?.playCount == 1 }
        fixture.factory.failingURLs = [fixture.original]
        manager.toggleReviewAudioBoost()
        #expect(!manager.isPlaying)
        #expect(fixture.factory.players[0].stopCount == 1)
        #expect(fixture.factory.players.count == 1)
    }

    @Test("Failure of automatic boost starts original playback")
    func automaticBoostFailurePlaysOriginal() async throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(enabled: true)
        defer { manager.reset() }
        manager.playPendingRecording()
        try await waitUntil { fixture.probe.waiters.count == 1 }
        manager.seekPlayback(to: 0.4)
        fixture.probe.fail()
        try await waitUntil { fixture.factory.players.first?.playCount == 1 }
        #expect(manager.reviewBoostState.hasFailed)
        #expect(fixture.factory.urls == [fixture.original])
        #expect(fixture.factory.players[0].currentTime == 4)
    }

    @Test("Automatic submission does not prepare a preview")
    func automaticSubmissionSkipsBoost() throws {
        let fixture = try ReviewBoostFixture()
        defer { fixture.cleanup() }
        let manager = fixture.manager(enabled: true, autoSubmit: true)
        #expect(manager.audioFilePath == fixture.original.lastPathComponent)
        #expect(manager.pendingPlaybackPath == nil)
        #expect(fixture.probe.requests.isEmpty)
        #expect(fixture.factory.players.isEmpty)
        manager.reset()
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }
}
