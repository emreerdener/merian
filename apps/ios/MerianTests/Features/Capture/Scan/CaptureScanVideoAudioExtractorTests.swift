import AVFoundation
import Foundation
@testable import Merian
import Testing

@Suite("Video companion audio extraction", .timeLimit(.minutes(1)))
struct CaptureScanVideoAudioExtractorTests {
    @Test(arguments: [1, 2])
    func preservesAACVideoAudioAsCanonicalInferenceWAV(channels: Int) async throws {
        let fixture = try await VideoAudioFixture(channels: channels)
        defer { fixture.remove() }
        let sourceBytes = try Data(contentsOf: fixture.videoURL)

        let lease = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL,
            outputDirectory: fixture.outputDirectory
        ))
        let outputURL = lease.fileURL
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: outputURL))
        #expect(InferenceAudioPreparer.isQueueEligibleInferenceAudioPath(outputURL.path))
        try MerianNetworkClient.validateInlineAudioFilesForInference(fileURLs: [outputURL])

        let audio = try AVAudioFile(forReading: outputURL)
        #expect(abs(Double(audio.length) - 44_100) < 2_048)
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: audio.processingFormat,
            frameCapacity: AVAudioFrameCount(audio.length)
        ))
        try audio.read(into: buffer)
        let samples = try #require(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).reduce(Float.zero) {
            max($0, abs(samples[$1]))
        }
        #expect(peak > 0.05, "Extraction must preserve audible samples, not just a valid header")
        #expect(try Data(contentsOf: fixture.videoURL) == sourceBytes)
        #expect(try fixture.outputFiles() == [outputURL])

        let acceptedURL = try await lease.relinquishOwnership()
        #expect(FileManager.default.fileExists(atPath: acceptedURL.path))
    }

    @Test func videoWithoutAudioProducesNoSidecar() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let lease = await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL,
            outputDirectory: fixture.outputDirectory
        )
        #expect(lease == nil)
        #expect(try fixture.outputFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    @Test func cancellationAndUnacceptedResultsLeaveNoSidecars() async throws {
        let fixture = try await VideoAudioFixture(channels: 2)
        defer { fixture.remove() }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await CaptureScanVideoAudioExtractor.extract(
                videoURL: fixture.videoURL,
                outputDirectory: fixture.outputDirectory
            )
        }
        #expect(await cancelled.value == nil)
        #expect(try fixture.outputFiles().isEmpty)

        try await extractAndDiscard(fixture)
        #expect(try fixture.outputFiles().isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    private func extractAndDiscard(_ fixture: VideoAudioFixture) async throws {
        let lease = try #require(await CaptureScanVideoAudioExtractor.extract(
            videoURL: fixture.videoURL,
            outputDirectory: fixture.outputDirectory
        ))
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: lease.fileURL))
    }
}

private struct VideoAudioFixture: Sendable {
    let root: URL
    let videoURL: URL
    let outputDirectory: URL

    init(channels: Int?) async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-audio-tests-\(UUID().uuidString)")
        videoURL = root.appendingPathComponent("capture.mp4")
        outputDirectory = root.appendingPathComponent("prepared")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        do {
            let silentURL = root.appendingPathComponent("silent.mp4")
            try await Self.writeSilentVideo(to: silentURL)
            guard let channels else {
                try FileManager.default.copyItem(at: silentURL, to: videoURL)
                return
            }
            let audioURL = root.appendingPathComponent("tone.m4a")
            try Self.writeAAC(to: audioURL, channels: channels)
            let composition = AVMutableComposition()
            for (url, mediaType) in [(silentURL, AVMediaType.video), (audioURL, .audio)] {
                let asset = AVURLAsset(url: url)
                let source = try #require(try await asset.loadTracks(withMediaType: mediaType).first)
                let track = try #require(composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ))
                try track.insertTimeRange(
                    CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 600)),
                    of: source,
                    at: .zero
                )
            }
            let exporter = try #require(AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetPassthrough
            ))
            try await exporter.export(to: videoURL, as: .mp4)
        } catch {
            remove()
            throw error
        }
    }

    func outputFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func writeAAC(to url: URL, channels: Int) throws {
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128_000
            ])
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: 48_000
            ))
            buffer.frameLength = 48_000
            let samples = try #require(buffer.floatChannelData)
            for channel in 0..<channels {
                for frame in 0..<48_000 {
                    samples[channel][frame] = Float(sin(2 * .pi * 880 * Double(frame) / 48_000) * 0.2)
                }
            }
            try file.write(from: buffer)
        }
    }

    private static func writeSilentVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ]
        )
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(
            kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB,
            nil, &pixelBuffer
        ) == kCVReturnSuccess)
        let pixels = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, 0, CVPixelBufferGetDataSize(pixels))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for frame in 0..<30 {
            let deadline = ContinuousClock.now + .seconds(5)
            while !input.isReadyForMoreMediaData, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try #require(input.isReadyForMoreMediaData)
            try #require(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}
