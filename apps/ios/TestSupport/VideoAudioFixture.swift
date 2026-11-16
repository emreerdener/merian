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
        print("VideoAudioFixture: waiting for encoder ownership")
        await Self.writerGate.acquire()
        print("VideoAudioFixture: encoder ownership acquired")
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
        print("VideoAudioFixture: silent video started")
        let silentURL = root.appendingPathComponent("silent.mp4")
        try await Self.writeSilentVideo(
            to: silentURL, width: width, height: height, frameCount: frameCount, transform: transform
        )
        print("VideoAudioFixture: silent video completed")
        guard let channels else {
            try FileManager.default.copyItem(at: silentURL, to: videoURL)
            return
        }
        let audioURL = root.appendingPathComponent("tone.m4a")
        print("VideoAudioFixture: AAC started")
        try Self.writeAAC(to: audioURL, channels: channels, amplitude: amplitude, frameCount: frameCount)
        print("VideoAudioFixture: AAC completed")
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
        print("VideoAudioFixture: composition export started")
        try await exporter.export(to: videoURL, as: .mp4)
        print("VideoAudioFixture: composition export completed")
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

    @MainActor private static func writeSilentVideo(
        to url: URL, width: Int, height: Int, frameCount: Int, transform: CGAffineTransform
    ) async throws {
        print("VideoAudioFixture: writer construction started")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        print("VideoAudioFixture: writer construction completed")
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.transform = transform
        print("VideoAudioFixture: writer input configured")
        // Keep encoder ownership until completion or cancellation, including
        // failure and the actual exit of every pending append.
        defer { if writer.status == .writing { writer.cancelWriting() } }
        if #available(iOS 26.0, *) {
            let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
            let pixels = CVReadOnlyPixelBuffer(unsafeBuffer: try blackPixels(width: width, height: height))
            print("VideoAudioFixture: receiver setup completed")
            try #require(writer.startWriting())
            print("VideoAudioFixture: writer start completed")
            writer.startSession(atSourceTime: .zero)
            print("VideoAudioFixture: receiver appends started")
            for frame in 0..<frameCount {
                do {
                    try await withReadinessDeadline {
                        try receiver.appendImmediately(pixels, with: CMTime(value: Int64(frame), timescale: 30))
                    }
                } catch ReadinessFailure.timedOut {
                    Issue.record("Fixture receiver exceeded five-second readiness deadline at frame \(frame), pre-cancel status \(writer.status.rawValue), writer error present \(writer.error != nil)")
                    throw ReadinessFailure.timedOut
                }
            }
            print("VideoAudioFixture: receiver appends completed")
            writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 30))
            receiver.finish()
            print("VideoAudioFixture: receiver finish completed")
        } else {
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
            )
            writer.add(input)
            try #require(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            let pixels = try blackPixels(width: width, height: height)
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
        }
        print("VideoAudioFixture: writer finalization started")
        await writer.finishWriting()
        print("VideoAudioFixture: writer finalization completed")
        try #require(writer.status == .completed)
    }

    private static func blackPixels(width: Int, height: Int) throws -> CVPixelBuffer {
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
        return pixels
    }

    enum ReadinessFailure: Error { case timedOut }

    /// Retry synchronous backpressure without leaving an append in flight.
    /// The caller may cancel its writer only after this helper returns/throws.
    @MainActor static func withReadinessDeadline(
        timeout: Duration = .seconds(5),
        operation: @MainActor () throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while true {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw ReadinessFailure.timedOut }
            let appended = try operation()
            try Task.checkCancellation()
            // A slow synchronous append must not clear an expired deadline.
            guard ContinuousClock.now < deadline else { throw ReadinessFailure.timedOut }
            if appended { return }
            try await Task.sleep(until: min(deadline, ContinuousClock.now + .milliseconds(5)), clock: .continuous)
        }
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
