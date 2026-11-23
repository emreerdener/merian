import AVFoundation
@testable import Merian
import Testing

@Suite("Video companion timeline", .serialized)
struct CaptureScanVideoAudioTimelineTests {
    @Test func nonzeroOriginAndSingleFrameRoundingHaveExactBounds() throws {
        let origin = CMTime(seconds: 2, preferredTimescale: 44_100)
        #expect(try CaptureScanVideoAudioTimeline.frameOffset(
            CMTime(seconds: 2.25, preferredTimescale: 44_100), origin: origin, frameLimit: 44_100) == 11_025)
        #expect(try CaptureScanVideoAudioTimeline.frameOffset(
            origin - CMTime(value: 1, timescale: 44_100), origin: origin, frameLimit: 44_100) == 0)
        #expect(throws: InferenceAudioPreparationError.invalidAudio) {
            try CaptureScanVideoAudioTimeline.frameOffset(
                origin - CMTime(value: 2, timescale: 44_100), origin: origin, frameLimit: 44_100)
        }
        #expect(throws: InferenceAudioPreparationError.invalidAudio) {
            try CaptureScanVideoAudioTimeline.frameOffset(.invalid, origin: origin, frameLimit: 44_100)
        }
    }

    @Test func internalEmptyEditPreservesBothSoundIntervals() async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let asset = AVURLAsset(url: fixture.videoURL)
        let source = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let edited = AVMutableComposition()
        let audio = try #require(edited.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        let clip = CMTimeRange(start: .zero, duration: CMTime(seconds: 0.2, preferredTimescale: 44_100))
        try audio.insertTimeRange(clip, of: source, at: CMTime(seconds: 0.1, preferredTimescale: 44_100))
        try audio.insertTimeRange(clip, of: source, at: CMTime(seconds: 0.6, preferredTimescale: 44_100))
        let output = try MediaProducerOutput(fileExtension: "wav")
        do {
            try await CaptureScanVideoAudioTimeline.write(asset: edited, output: output)
            let samples = try readSamples(output.outputURL)
            let origin = try await audio.load(.timeRange).start.seconds
            func peak(_ start: Double, _ end: Double) -> Float {
                let lower = Int(((start - origin) * 44_100).rounded())
                let upper = Int(((end - origin) * 44_100).rounded())
                guard lower >= 0, upper <= samples.count, upper > lower else { return -1 }
                return samples[lower..<upper].reduce(0) { max($0, abs($1)) }
            }
            #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: output.outputURL))
            #expect(abs(Double(samples.count) / 44_100 - (0.8 - origin)) < 0.002)
            #expect(peak(0.14, 0.25) > 0.05)
            #expect(peak(0.4, 0.5) == 0)
            #expect(peak(0.64, 0.75) > 0.05)
            try await output.discardAfterExit()
        } catch {
            _ = await FileIOActor.shared.settleProducerCleanup(owner: output) { try await output.discardAfterExit() }
            throw error
        }
    }

    @Test func silentEditCannotBypassPCMByteBudget() async throws {
        let fixture = try await VideoAudioFixture(channels: 1)
        defer { fixture.remove() }
        let asset = AVURLAsset(url: fixture.videoURL)
        let source = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let edited = AVMutableComposition()
        let audio = try #require(edited.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        let excessiveOffset = Double(ScanMediaPayloadPolicy.maxInferenceAudioBytes) / 88_200 + 1
        let clip = CMTimeRange(start: .zero, duration: CMTime(seconds: 0.2, preferredTimescale: 44_100))
        try audio.insertTimeRange(clip, of: source, at: .zero)
        try audio.insertTimeRange(clip, of: source,
            at: CMTime(seconds: excessiveOffset, preferredTimescale: 44_100))
        let range = try await audio.load(.timeRange)
        #expect(range.start == .zero)
        #expect(range.duration.seconds * 88_200 > Double(ScanMediaPayloadPolicy.maxInferenceAudioBytes))
        let output = try MediaProducerOutput(fileExtension: "wav")
        do {
            await #expect(throws: InferenceAudioPreparationError.payloadTooLarge) {
                try await CaptureScanVideoAudioTimeline.write(asset: edited, output: output)
            }
            #expect(!FileManager.default.fileExists(atPath: output.outputURL.path))
            try await output.discardAfterExit()
        } catch {
            _ = await FileIOActor.shared.settleProducerCleanup(owner: output) { try await output.discardAfterExit() }
            throw error
        }
    }

    private func readSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
