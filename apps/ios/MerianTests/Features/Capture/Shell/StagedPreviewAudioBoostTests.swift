import AVFoundation
import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Staged preview audio boost")
struct StagedPreviewAudioBoostTests {
    @Test func localCopyIsReusedAndReleasedWithoutChangingOriginal() async throws {
        let fixture = try await VideoAudioFixture(channels: 1, amplitude: 0.01)
        defer { fixture.remove() }
        let audio = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL, outputDirectory: fixture.outputDirectory
        ))
        let original = try Data(contentsOf: audio.fileURL)
        let source = StagedPreviewAudioBoostSource()
        let dependencies = source.playbackDependencies(base: .init())
        let boosted = try await dependencies.prepareAudioBoost(audio.fileURL.path)
        #expect(boosted.gainDecibels > 0)
        #expect(boosted.url != audio.fileURL)
        let second = try await dependencies.prepareAudioBoost(audio.fileURL.path)
        #expect(second.url == boosted.url)
        #expect(FileManager.default.fileExists(atPath: boosted.url.path))
        await dependencies.releaseAudioBoost(audio.fileURL.path)
        #expect(!FileManager.default.fileExists(atPath: boosted.url.path))
        #expect(try Data(contentsOf: audio.fileURL) == original)
    }

    @Test func latePreparationAfterDismissalDeletesOnlyDerivative() async throws {
        let original = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let boosted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: original)
        try Data([2]).write(to: boosted)
        defer {
            try? FileManager.default.removeItem(at: original)
            try? FileManager.default.removeItem(at: boosted)
        }
        let probe = StagedBoostProbe()
        let source = StagedPreviewAudioBoostSource(dependencies: .init(
            prepare: { try await probe.prepare($0) },
            remove: { try? FileManager.default.removeItem(at: $0) }
        ))
        let task = Task { try await source.prepare(source: original.path) }
        try await waitUntil { probe.continuation != nil }
        source.release()
        probe.continuation?.resume(returning: .init(url: boosted, gainDecibels: 12))
        do {
            _ = try await task.value
            Issue.record("Dismissed preparation returned a usable result")
        } catch is CancellationError { }
        #expect(!FileManager.default.fileExists(atPath: boosted.path))
        #expect(try Data(contentsOf: original) == Data([1]))
    }

    @Test func compositionRetainsPictureDurationAndUsesOnlyBoostedSoundtrack() async throws {
        let fixture = try await VideoAudioFixture(channels: 2, amplitude: 0.01)
        defer { fixture.remove() }
        let original = try Data(contentsOf: fixture.videoURL)
        let audio = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL, outputDirectory: fixture.outputDirectory
        ))
        let source = StagedPreviewAudioBoostSource()
        defer { source.release() }
        let result = try await source.prepare(source: audio.fileURL.path)
        let item = try await StagedVideoPreviewComposition.makeItem(
            videoURL: fixture.videoURL, boostedAudioURL: result.url
        )
        let asset = try #require(item.asset as? AVComposition)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(videoTracks.count == 1)
        #expect(audioTracks.count == 1)
        let track = try #require(audioTracks.first)
        #expect(track.segments.compactMap(\.sourceURL) == [result.url])
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.05)
        #expect(try Data(contentsOf: fixture.videoURL) == original)
    }

    @Test func compositionPreservesRotationAndExtractedSoundtrackTiming() async throws {
        let fixture = try await VideoAudioFixture(channels: 1, amplitude: 0.01)
        defer { fixture.remove() }
        let original = AVURLAsset(url: fixture.videoURL)
        let video = try #require(try await original.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await original.loadTracks(withMediaType: .audio).first)
        let shifted = AVMutableComposition()
        let picture = try #require(shifted.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ))
        try picture.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
            of: video, at: .zero
        )
        picture.preferredTransform = CGAffineTransform(rotationAngle: .pi / 2)
        let soundtrack = try #require(shifted.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ))
        try soundtrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 0.5, preferredTimescale: 600)),
            of: audio, at: CMTime(seconds: 0.25, preferredTimescale: 600)
        )
        let shiftedURL = fixture.root.appendingPathComponent("offset.mp4")
        let export = try #require(AVAssetExportSession(asset: shifted, presetName: AVAssetExportPresetPassthrough))
        try await export.export(to: shiftedURL, as: .mp4)
        let companion = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: shiftedURL, outputDirectory: fixture.outputDirectory
        ))
        let source = StagedPreviewAudioBoostSource()
        defer { source.release() }
        let result = try await source.prepare(source: companion.fileURL.path)
        let item = try await StagedVideoPreviewComposition.makeItem(
            videoURL: shiftedURL, boostedAudioURL: result.url
        )
        let outputVideo = try #require(try await item.asset.loadTracks(withMediaType: .video).first)
        let outputAudio = try #require(try await item.asset.loadTracks(withMediaType: .audio).first as? AVCompositionTrack)
        let segment = try #require(outputAudio.segments.first(where: { !$0.isEmpty }))
        #expect(segment.timeMapping.target.end.seconds <= 1.03)
        let soundFile = try AVAudioFile(forReading: result.url)
        let samples = try #require(AVAudioPCMBuffer(
            pcmFormat: soundFile.processingFormat, frameCapacity: AVAudioFrameCount(soundFile.length)
        ))
        try soundFile.read(into: samples)
        let channel = try #require(samples.floatChannelData?[0])
        let firstSound = try #require((0..<Int(samples.frameLength)).first { abs(channel[$0]) > 0.001 })
        let audibleStart = segment.timeMapping.target.start.seconds
            + Double(firstSound) / soundFile.processingFormat.sampleRate
            - segment.timeMapping.source.start.seconds
        #expect(abs(audibleStart - 0.25) < 0.03)
        let transform = try await outputVideo.load(.preferredTransform)
        #expect(abs(transform.b - 1) < 0.01)
        #expect(abs(try await item.asset.load(.duration).seconds - 1) < 0.03)
    }

    @Test func videoTogglePreservesPausedPositionAndCleansUp() async throws {
        let fixture = try await VideoAudioFixture(channels: 1, amplitude: 0.01)
        defer { fixture.remove() }
        let audio = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL, outputDirectory: fixture.outputDirectory
        ))
        let source = StagedPreviewAudioBoostSource()
        let playback = StagedVideoPreviewPlayback(
            video: .init(filePath: fixture.videoURL.path, sampledImages: [], audioFilePath: audio.fileURL.path),
            boostSource: source, session: makeSession()
        )
        defer { playback.stop() }
        await playback.start()
        playback.player.pause()
        #expect(await playback.player.seek(to: CMTime(seconds: 0.4, preferredTimescale: 600)))
        playback.toggleBoost()
        try await waitUntil { !playback.isPreparing }
        #expect(playback.isBoostEnabled)
        #expect(!playback.hasBoostFailure)
        #expect(playback.player.rate == 0)
        #expect(abs(playback.player.currentTime().seconds - 0.4) < 0.05)
        let boosted = try await source.prepare(source: audio.fileURL.path)
        playback.toggleBoost()
        try await waitUntil { !playback.isPreparing }
        #expect(!playback.isBoostEnabled)
        #expect(playback.player.rate == 0)
        #expect(abs(playback.player.currentTime().seconds - 0.4) < 0.05)
        playback.stop()
        #expect(playback.player.currentItem == nil)
        #expect(!FileManager.default.fileExists(atPath: boosted.url.path))
        #expect(FileManager.default.fileExists(atPath: audio.fileURL.path))
    }

    @Test func failedSourceSeekRestoresOriginalItemAndPosition() async throws {
        let fixture = try await VideoAudioFixture(channels: 1, amplitude: 0.01)
        defer { fixture.remove() }
        let audio = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL, outputDirectory: fixture.outputDirectory
        ))
        var seekCount = 0
        let playback = StagedVideoPreviewPlayback(
            video: .init(filePath: fixture.videoURL.path, sampledImages: [], audioFilePath: audio.fileURL.path),
            session: makeSession(),
            dependencies: .init(seek: { player, time in
                seekCount += 1
                guard seekCount > 1 else { return false }
                return await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            })
        )
        defer { playback.stop() }
        await playback.start()
        playback.player.pause()
        #expect(await playback.player.seek(to: CMTime(seconds: 0.4, preferredTimescale: 600)))
        let original = playback.player.currentItem
        playback.toggleBoost()
        try await waitUntil { !playback.isPreparing }
        #expect(playback.hasBoostFailure)
        #expect(!playback.isBoostEnabled)
        #expect(playback.player.currentItem === original)
        #expect(playback.player.rate == 0)
        #expect(abs(playback.player.currentTime().seconds - 0.4) < 0.05)
    }

    @Test func preparationFailureKeepsOriginalAndSilentVideoHasNoBoost() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let silent = StagedVideoPreviewPlayback(
            video: .init(filePath: fixture.videoURL.path, sampledImages: []), session: makeSession()
        )
        #expect(!silent.canBoost)
        await silent.start()
        silent.toggleBoost()
        #expect(!silent.isPreparing)
        silent.stop()

        let audio = fixture.root.appendingPathComponent("tone.wav")
        try Data([1]).write(to: audio)
        let failure = StagedPreviewAudioBoostSource(dependencies: .init(
            prepare: { _ in throw CocoaError(.fileReadCorruptFile) }, remove: { _ in }
        ))
        let playback = StagedVideoPreviewPlayback(
            video: .init(filePath: fixture.videoURL.path, sampledImages: [], audioFilePath: audio.path),
            boostSource: failure, session: makeSession()
        )
        await playback.start()
        let original = playback.player.currentItem
        playback.toggleBoost()
        try await waitUntil { !playback.isPreparing }
        #expect(playback.hasBoostFailure)
        #expect(!playback.isBoostEnabled)
        #expect(playback.player.currentItem === original)
        playback.stop()
    }

    @Test func dismissalDuringCompositionCannotInstallOrResumeLateItem() async throws {
        let fixture = try await VideoAudioFixture(channels: 1, amplitude: 0.01)
        defer { fixture.remove() }
        let audio = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL, outputDirectory: fixture.outputDirectory
        ))
        let source = StagedPreviewAudioBoostSource()
        var continuation: CheckedContinuation<AVPlayerItem, Error>?
        var playRequestCount = 0
        let playback = StagedVideoPreviewPlayback(
            video: .init(filePath: fixture.videoURL.path, sampledImages: [], audioFilePath: audio.fileURL.path),
            boostSource: source, session: makeSession(),
            dependencies: .init(play: { player in
                playRequestCount += 1
                player.play()
            }, makeBoostedItem: { _, _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            })
        )
        defer { playback.stop() }
        await playback.start()
        #expect(playRequestCount == 1)
        let preparation = try #require(playback.toggleBoost())
        try await waitUntil { continuation != nil }
        let result = try await source.prepare(source: audio.fileURL.path)
        playback.stop()
        continuation?.resume(returning: AVPlayerItem(url: fixture.videoURL))
        await preparation.value
        #expect(playback.player.currentItem == nil)
        // With no current item, AVPlayer's rate is not a playback-ownership
        // signal. Check that the completed stale task issued no play request.
        #expect(playRequestCount == 1)
        #expect(!playback.isPreparing)
        #expect(!FileManager.default.fileExists(atPath: result.url.path))
    }

    @Test func backgroundDuringSeekCannotResumeAndKeepsInstalledBoostState() async throws {
        let fixture = try await VideoAudioFixture(channels: 1, amplitude: 0.01)
        defer { fixture.remove() }
        let audio = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL, outputDirectory: fixture.outputDirectory
        ))
        var continuation: CheckedContinuation<Bool, Never>?
        let playback = StagedVideoPreviewPlayback(
            video: .init(filePath: fixture.videoURL.path, sampledImages: [], audioFilePath: audio.fileURL.path),
            session: makeSession(),
            dependencies: .init(seek: { _, _ in
                await withCheckedContinuation { continuation = $0 }
            })
        )
        defer { playback.stop() }
        await playback.start()
        let preparation = try #require(playback.toggleBoost())
        try await waitUntil { continuation != nil }
        playback.pauseForBackground()
        continuation?.resume(returning: true)
        await preparation.value
        #expect(playback.isBoostEnabled)
        #expect(!playback.isPreparing)
        #expect(playback.player.rate == 0)
    }

    private func makeSession() -> AudioPlaybackSessionController {
        let coordinator = AudioSessionCoordinator(operations: .init(configureAndActivate: { _ in }, deactivate: {}))
        return AudioPlaybackSessionController(dependencies: .init(
            activate: { try await coordinator.activate($0) },
            deactivate: { await coordinator.deactivate(ifCurrent: $0) },
            isCurrent: { await coordinator.isCurrent($0) }
        ))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

@MainActor
private final class StagedBoostProbe {
    var continuation: CheckedContinuation<AudioBoostResult, Error>?
    func prepare(_ source: URL) async throws -> AudioBoostResult {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
