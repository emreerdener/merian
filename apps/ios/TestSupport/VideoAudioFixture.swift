import AVFoundation
import Foundation
import Testing

struct VideoAudioFixture: Sendable {
    let root: URL
    let videoURL: URL
    let outputDirectory: URL

    init(
        channels: Int?, amplitude: Double = 0.2,
        width: Int = 64, height: Int = 64, frameCount: Int = 30,
        transform: CGAffineTransform = .identity
    ) async throws {
        try #require((2...2048).contains(width) && width.isMultiple(of: 2))
        try #require((2...2048).contains(height) && height.isMultiple(of: 2))
        try #require((3...150).contains(frameCount))
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-audio-tests-\(UUID().uuidString)")
        videoURL = root.appendingPathComponent("capture.mp4")
        outputDirectory = root.appendingPathComponent("prepared")
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        await Self.writerGate.acquire()
        do {
            try Task.checkCancellation()
            try await prepare(
                channels: channels, amplitude: amplitude, width: width, height: height,
                frameCount: frameCount, transform: transform
            )
            await Self.writerGate.release()
        } catch {
            remove()
            await Self.writerGate.release()
            throw error
        }
    }

    /// Keep the fixture's encoder permit through AAC creation and composition export.
    private func prepare(
        channels: Int?, amplitude: Double, width: Int, height: Int,
        frameCount: Int, transform: CGAffineTransform
    ) async throws {
        let silentURL = root.appendingPathComponent("silent.mp4")
        try await Self.writeSilentVideo(
            to: silentURL, width: width, height: height, frameCount: frameCount, transform: transform
        )
        guard let channels else {
            try FileManager.default.copyItem(at: silentURL, to: videoURL)
            return
        }
        let audioURL = root.appendingPathComponent("tone.m4a")
        try Self.writeAAC(to: audioURL, channels: channels, amplitude: amplitude, frameCount: frameCount)
        let composition = AVMutableComposition()
        for (url, mediaType) in [(silentURL, AVMediaType.video), (audioURL, .audio)] {
            let asset = AVURLAsset(url: url)
            let source = try #require(try await asset.loadTracks(withMediaType: mediaType).first)
            let track = try #require(composition.addMutableTrack(
                withMediaType: mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ))
            if mediaType == .video { track.preferredTransform = transform }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(value: Int64(frameCount), timescale: 30)),
                of: source,
                at: .zero
            )
        }
        let exporter = try #require(AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ))
        try await exporter.export(to: videoURL, as: .mp4)
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

    private static func writeAAC(to url: URL, channels: Int, amplitude: Double, frameCount: Int) throws {
        let sampleCount = frameCount * 1600
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128_000
            ])
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(sampleCount)
            ))
            buffer.frameLength = AVAudioFrameCount(sampleCount)
            let samples = try #require(buffer.floatChannelData)
            for channel in 0..<channels {
                for frame in 0..<sampleCount {
                    samples[channel][frame] = Float(sin(2 * .pi * 880 * Double(frame) / 48_000) * amplitude)
                }
            }
            try file.write(from: buffer)
        }
    }

    private static let writerGate = VideoFixtureWriterGate()

    private static func writeSilentVideo(
        to url: URL, width: Int, height: Int, frameCount: Int, transform: CGAffineTransform
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        input.transform = transform
        writer.add(input)
        // Keep encoder ownership until completion or cancellation, including
        // failed assertions and cancellation during fixture preparation.
        defer {
            if writer.status == .writing { writer.cancelWriting() }
        }
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixelBuffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB,
            nil, &pixelBuffer
        ) == kCVReturnSuccess)
        let pixels = try #require(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, 0, CVPixelBufferGetDataSize(pixels))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for frame in 0..<frameCount {
            try Task.checkCancellation()
            let deadline = ContinuousClock.now + .seconds(5)
            while !input.isReadyForMoreMediaData, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            try #require(
                input.isReadyForMoreMediaData,
                "Fixture writer stalled at frame \(frame), status \(writer.status.rawValue), error \(String(describing: writer.error))"
            )
            try #require(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 30))
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}

// Synthetic encoders share process resources even when Swift Testing runs
// independent suites concurrently. No production capture ownership uses this.
private actor VideoFixtureWriterGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !occupied {
            occupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            occupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
