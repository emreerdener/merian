import AVFoundation
import CryptoKit
import Foundation
@testable import Merian
import Testing

@Suite(.serialized)
struct ObservationVideoAudioDeriverTests {
    @Test(arguments: [1, 2])
    func retainedPCMHasExactCountAndDigest(channels: Int) async throws {
        let fixture = try await VideoAudioFixture(channels: channels)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        let id = UUID()
        let output = try #require(try await ObservationVideoAudioDeriver().derive(source: clip, sourceMediaID: id, directory: fixture.outputDirectory))
        let bytes = try Data(contentsOf: output.file)
        let inspection = try #require(ObservationAudioContainer.inspect(bytes))
        #expect(inspection.dataOffset == 44)
        #expect(inspection.sampleCount == output.audio.sampleCount)
        #expect(output.audio.sourceMediaID == id && output.source.mediaID == id)
        #expect(output.audio.artifact.mediaID != id)
        #expect(output.audio.artifact.byteCount == bytes.count)
        #expect(output.audio.artifact.sha256 == hash(bytes))
        #expect(output.source.sha256 == hash(try Data(contentsOf: clip.url)))
        #expect(abs(output.audio.sampleCount * 600 - (output.audio.endTicks - output.audio.startTicks) * 44_100) <= 44_100)
        #expect(bytes.dropFirst(44).contains { $0 != 0 })
    }

    @Test func silentClipHasNoCompanionAndReleasesUse() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        #expect(try await ObservationVideoAudioDeriver().derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory) == nil)
        #expect(try fixture.outputFiles().count == 1)
        #expect(try await clip.relinquishOwnership() == clip.url)
    }

    @Test(arguments: [false, true])
    func shortOffsetAudioUsesMeasuredInterval(transcode: Bool) async throws {
        let fixture = try await VideoAudioFixture(channels: 2)
        defer { fixture.remove() }
        let asset = AVURLAsset(url: fixture.videoURL)
        let composition = AVMutableComposition()
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let videoTrack = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 600, timescale: 600)), of: video, at: .zero)
        let audioTrack = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 240, timescale: 600)), of: audio,
                                       at: CMTime(value: 180, timescale: 600))
        let export = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        let offset = fixture.root.appendingPathComponent("offset.mp4")
        try await export.export(to: offset, as: .mp4)
        let clip: ObservationRetainedVideoClip
        if transcode {
            clip = try await ObservationRetainedVideoClipProducer().prepare(source: offset, directory: fixture.outputDirectory)
        } else {
            // Compare direct composition decoding with the retained transcode.
            // Both can decode a leading empty edit into actual PCM silence.
            let owned = fixture.outputDirectory.appendingPathComponent("synthetic-offset", isDirectory: true)
            try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
            let saved = owned.appendingPathComponent("retained.mp4")
            try FileManager.default.copyItem(at: offset, to: saved)
            clip = ObservationRetainedVideoClip(url: saved, ownedDirectory: owned)
        }
        let output = try #require(try await ObservationVideoAudioDeriver().derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory))
        #expect(output.audio.startTicks == 0)
        #expect(output.audio.sampleCount < 44_100)
        #expect(output.audio.endTicks < 600)
        // Independent decoder verifies exact PCM, count and endpoint association.
        let retained = AVURLAsset(url: clip.url)
        let track = try #require(try await retained.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: retained)
        defer { reader.cancelReading() }
        let decoder = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(decoder)
        #expect(reader.startReading())
        var first: CMTime?
        var last = CMTime.zero
        var samples = 0
        var pcm = Data()
        while let buffer = decoder.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
            let count = CMSampleBufferGetNumSamples(buffer)
            if first == nil { first = pts }
            last = CMTimeAdd(pts, CMTime(value: Int64(count), timescale: 44_100))
            samples += count
            let block = try #require(CMSampleBufferGetDataBuffer(buffer))
            var chunk = Data(count: count * 2)
            let status = chunk.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 2, destination: bytes.baseAddress!)
            }
            #expect(status == kCMBlockBufferNoErr)
            pcm.append(chunk)
        }
        #expect(reader.status == .completed)
        #expect(output.audio.sampleCount == samples)
        #expect(output.audio.startTicks == Int(CMTimeConvertScale(try #require(first), timescale: 600, method: .roundHalfAwayFromZero).value))
        #expect(output.audio.endTicks == Int(CMTimeConvertScale(last, timescale: 600, method: .roundHalfAwayFromZero).value))
        #expect(try Data(contentsOf: output.file).dropFirst(44) == pcm)
    }

    @Test func cancellationJoinsWorkerAndReleasesSlot() async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        let checkpoint = VideoAudioCheckpoint()
        let producer = ObservationVideoAudioDeriver(validateAfterBuffer: { _ in
            if await checkpoint.first() { try await Task.sleep(for: .seconds(30)) }
        })
        let task = Task { try await producer.derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory) }
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await checkpoint.entered), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await checkpoint.entered)
        do { _ = try await clip.relinquishOwnership(); Issue.record("Borrowed source transferred") } catch ObservationRetainedVideoClipError.busy {}
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled extraction succeeded") } catch is CancellationError {}
        #expect(try fixture.outputFiles().count == 1)
        #expect(try await producer.derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory) != nil)
    }

    @Test(arguments: [false, true]) func changedSourceThrowsAndRetainsNoOutput(afterWrite: Bool) async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        let mutate: @Sendable () throws -> Void = {
                let handle = try FileHandle(forWritingTo: clip.url)
                defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: Data([0]))
        }
        let producer = ObservationVideoAudioDeriver(validateAfterWrite: {
            if afterWrite { try mutate() }
        }, validateAfterBuffer: { index in
            if !afterWrite && index == 1 { try mutate() }
        })
        do { _ = try await producer.derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory); Issue.record("Changed source accepted") } catch ObservationVideoAudioError.sourceChanged {}
        #expect(try fixture.outputFiles().count == 1)
    }

    @Test func droppedResultRemovesDirectoryAndReleasesTransfer() async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let clip = try await ObservationRetainedVideoClipProducer().prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        var output = try await ObservationVideoAudioDeriver().derive(source: clip, sourceMediaID: UUID(), directory: fixture.outputDirectory)
        let directory = try #require(output?.file).deletingLastPathComponent()
        do { _ = try await clip.relinquishOwnership(); Issue.record("Retained result lost source") } catch ObservationRetainedVideoClipError.busy {}
        output = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try await clip.relinquishOwnership() == clip.url)
    }

    @Test func nonzeroPCMIntervalUsesSampleDurationAndRejectsDiscontinuity() throws {
        var timeline = ObservationVideoAudioTimeline()
        try timeline.append(presentationTime: CMTime(value: 3, timescale: 10), sampleCount: 4410)
        try timeline.append(presentationTime: CMTime(value: 4, timescale: 10), sampleCount: 4410)
        let interval = try timeline.interval(durationTicks: 600)
        #expect(interval.start == 180 && interval.end == 300)
        #expect(timeline.sampleCount == 8820)
        for time in [CMTime(value: 49, timescale: 100), CMTime(value: 51, timescale: 100), .invalid, .indefinite] {
            var candidate = timeline
            #expect(throws: ObservationVideoAudioError.self) { try candidate.append(presentationTime: time, sampleCount: 1) }
            #expect(candidate.sampleCount == 8820)
        }
        #expect(throws: ObservationVideoAudioError.self) { try timeline.interval(durationTicks: 299) }
    }

    @Test func emptyInvalidAndOversizedPCMFailBeforeAdmission() throws {
        let empty = ObservationVideoAudioTimeline()
        #expect(throws: ObservationVideoAudioError.self) { try empty.interval(durationTicks: 600) }
        for count in [0, -1, 220_501] {
            var candidate = empty
            #expect(throws: ObservationVideoAudioError.self) { try candidate.append(presentationTime: .zero, sampleCount: count) }
            #expect(candidate.sampleCount == 0)
        }
        var maximum = empty
        try maximum.append(presentationTime: .zero, sampleCount: 220_500)
        #expect(try maximum.interval(durationTicks: 3000).end == 3000)
        #expect(throws: ObservationVideoAudioError.self) { try maximum.append(presentationTime: CMTime(value: 5, timescale: 1), sampleCount: 1) }
        #expect(maximum.sampleCount == 220_500)
    }

    private func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}

private actor VideoAudioCheckpoint {
    private(set) var entered = false
    func first() -> Bool {
        guard !entered else { return false }
        entered = true
        return true
    }
}
