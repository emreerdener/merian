// Offline synthetic asset authoring only. Never invoked by test setup or CI.
// Compile with xcrun swiftc -parse-as-library, using a disposable module cache and executable.
// See docs/development-guides/08-testing-strategy.md for the authoring procedure.
// Run with a new output directory, then review and copy the manifest and MP4s.
import AVFoundation
import CryptoKit
import Foundation

private struct GeneratedVideoAudioFixture: Sendable {
    let root: URL
    let videoURL: URL
    let outputDirectory: URL

    init(
        channels: Int?, amplitude: Double = 0.2,
        width: Int = 64, height: Int = 64, frameCount: Int = 30,
        transform: CGAffineTransform = .identity, coordinatePattern: Bool = false
    ) async throws {
        try required((2...2048).contains(width) && width.isMultiple(of: 2))
        try required((2...2048).contains(height) && height.isMultiple(of: 2))
        try required((3...150).contains(frameCount))
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
                frameCount: frameCount, transform: transform, coordinatePattern: coordinatePattern
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
        frameCount: Int, transform: CGAffineTransform, coordinatePattern: Bool
    ) async throws {
        print("VideoAudioFixture: silent video started")
        let silentURL = root.appendingPathComponent("silent.mp4")
        try await Self.writeSilentVideo(
            to: silentURL, width: width, height: height, frameCount: frameCount, transform: transform, coordinatePattern: coordinatePattern
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
            let source = try required(try await asset.loadTracks(withMediaType: mediaType).first)
            let track = try required(composition.addMutableTrack(
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
        let exporter = try required(AVAssetExportSession(
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
            let buffer = try required(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(sampleCount)
            ))
            buffer.frameLength = AVAudioFrameCount(sampleCount)
            let samples = try required(buffer.floatChannelData)
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
        to url: URL, width: Int, height: Int, frameCount: Int, transform: CGAffineTransform, coordinatePattern: Bool
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
            let pixels = CVReadOnlyPixelBuffer(unsafeBuffer: try fixturePixels(width: width, height: height, coordinatePattern: coordinatePattern))
            print("VideoAudioFixture: receiver setup completed")
            try required(writer.startWriting())
            print("VideoAudioFixture: writer start completed")
            writer.startSession(atSourceTime: .zero)
            print("VideoAudioFixture: receiver appends started")
            for frame in 0..<frameCount {
                try await withReadinessDeadline(onTimeout: { observation in
                    print("Fixture receiver exceeded five-second readiness deadline at frame \(frame), pre-cancel status \(writer.status.rawValue), writer error present \(writer.error != nil); \(observation.summary)")
                }) {
                    try receiver.appendImmediately(pixels, with: CMTime(value: Int64(frame), timescale: 30))
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
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
                ]
            )
            writer.add(input)
            try required(writer.startWriting())
            writer.startSession(atSourceTime: .zero)
            let pixels = try fixturePixels(width: width, height: height, coordinatePattern: coordinatePattern)
            for frame in 0..<frameCount {
                try Task.checkCancellation()
                let deadline = ContinuousClock.now + .seconds(5)
                while !input.isReadyForMoreMediaData, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(5))
                }
                try required(
                    input.isReadyForMoreMediaData,
                    "Fixture writer stalled at frame \(frame), status \(writer.status.rawValue), error \(String(describing: writer.error))"
                )
                try required(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
            }
            writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: 30))
            input.markAsFinished()
        }
        print("VideoAudioFixture: writer finalization started")
        await writer.finishWriting()
        print("VideoAudioFixture: writer finalization completed")
        try required(writer.status == .completed)
    }

    private static func fixturePixels(width: Int, height: Int, coordinatePattern: Bool) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        try required(CVPixelBufferCreate(
            // AVAssetWriter recommends BGRA when supplying RGB buffers on iOS.
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
            nil, &pixelBuffer
        ) == kCVReturnSuccess)
        let pixels = try required(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let base = CVPixelBufferGetBaseAddress(pixels) {
            memset(base, 0, CVPixelBufferGetDataSize(pixels))
            if coordinatePattern {
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(pixels)
                for y in 0..<height {
                    for x in 0..<width {
                        let index = y * stride + x * 4
                        // BGRA encodes the same synthetic x/red, y/green gradient
                        // used by Capture's original ARGB fixture.
                        bytes[index] = 64
                        bytes[index + 1] = UInt8(y * 255 / max(1, height - 1))
                        bytes[index + 2] = UInt8(x * 255 / max(1, width - 1))
                        bytes[index + 3] = 255
                    }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return pixels
    }

    enum ReadinessFailure: Error { case timedOut }

    struct ReadinessTimeoutObservation: Sendable {
        let attempts: Int
        let backpressureCount: Int
        let lastAppendResult: Bool?
        let appendDuration: Duration
        let longestAppendDuration: Duration
        let elapsed: Duration

        var summary: String {
            let result = lastAppendResult.map { $0 ? "accepted" : "backpressure" } ?? "not-attempted"
            return "attempts \(attempts), backpressure returns \(backpressureCount), last result \(result), total append time \(appendDuration), longest append \(longestAppendDuration), elapsed \(elapsed)"
        }
    }

    /// Retry synchronous backpressure without leaving an append in flight.
    /// The caller may cancel its writer only after this helper returns/throws.
    @MainActor static func withReadinessDeadline(
        timeout: Duration = .seconds(5),
        onTimeout: @MainActor (ReadinessTimeoutObservation) -> Void = { _ in },
        operation: @MainActor () throws -> Bool
    ) async throws {
        let started = ContinuousClock.now
        let deadline = started + timeout
        var attempts = 0
        var backpressureCount = 0
        var lastAppendResult: Bool?
        var appendDuration = Duration.zero
        var longestAppendDuration = Duration.zero
        do {
            while true {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else { throw ReadinessFailure.timedOut }
                attempts += 1
                let appendStarted = ContinuousClock.now
                let appended = try operation()
                let duration = appendStarted.duration(to: .now)
                appendDuration += duration
                longestAppendDuration = max(longestAppendDuration, duration)
                lastAppendResult = appended
                if !appended { backpressureCount += 1 }
                try Task.checkCancellation()
                // A slow synchronous append must not clear an expired deadline.
                guard ContinuousClock.now < deadline else { throw ReadinessFailure.timedOut }
                if appended { return }
                try await Task.sleep(until: min(deadline, ContinuousClock.now + .milliseconds(5)), clock: .continuous)
            }
        } catch ReadinessFailure.timedOut {
            onTimeout(ReadinessTimeoutObservation(
                attempts: attempts, backpressureCount: backpressureCount, lastAppendResult: lastAppendResult,
                appendDuration: appendDuration, longestAppendDuration: longestAppendDuration,
                elapsed: started.duration(to: .now)
            ))
            throw ReadinessFailure.timedOut
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

private func required<T>(_ value: T?) throws -> T {
    guard let value else { throw FixtureAuthoringFailure.invalid }
    return value
}
private func required(_ value: Bool, _ message: String = "Invalid synthetic fixture") throws {
    guard value else { throw FixtureAuthoringFailure.invalid }
}
private enum FixtureAuthoringFailure: Error { case invalid }

private struct FixtureSpec: Codable {
    let name: String
    let channels: Int?
    let amplitude: Double
    let width: Int
    let height: Int
    let frameCount: Int
    let transform: [Double]
    var coordinatePattern: Bool = false
    var byteCount: Int = 0
    var sha256: String = ""
    var affine: CGAffineTransform {
        .init(a: transform[0], b: transform[1], c: transform[2], d: transform[3], tx: transform[4], ty: transform[5])
    }
}
private struct FixtureCatalog: Codable {
    let version: Int
    let provenance: String
    let fixtures: [FixtureSpec]
}

@main private struct GenerateVideoFixtures {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw FixtureAuthoringFailure.invalid }
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw FixtureAuthoringFailure.invalid }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let identity = [1.0, 0, 0, 1, 0, 0]
        var specs = [
            FixtureSpec(name: "silent", channels: nil, amplitude: 0.2, width: 64, height: 64, frameCount: 30, transform: identity),
            FixtureSpec(name: "mono", channels: 1, amplitude: 0.2, width: 64, height: 64, frameCount: 30, transform: identity),
            FixtureSpec(name: "stereo", channels: 2, amplitude: 0.2, width: 64, height: 64, frameCount: 30, transform: identity),
            FixtureSpec(name: "quiet-mono", channels: 1, amplitude: 0.01, width: 64, height: 64, frameCount: 30, transform: identity),
            FixtureSpec(name: "quiet-stereo", channels: 2, amplitude: 0.01, width: 64, height: 64, frameCount: 30, transform: identity)
        ]
        for frames in [3, 150] {
            specs.append(.init(name: "rotated-silent-\(frames)", channels: nil, amplitude: 0.2, width: 96, height: 64,
                               frameCount: frames, transform: [0, 1, -1, 0, 64, 0]))
            specs.append(.init(name: "mirrored-stereo-\(frames)", channels: 2, amplitude: 0.2, width: 96, height: 64,
                               frameCount: frames, transform: [-1, 0, 0, 1, 96, 0]))
        }
        specs += [
            .init(name: "portrait-silent", channels: nil, amplitude: 0.2, width: 96, height: 160,
                  frameCount: 30, transform: identity),
            .init(name: "portrait-rotated-silent", channels: nil, amplitude: 0.2, width: 96, height: 160,
                  frameCount: 30, transform: [0, 1, -1, 0, 160, 0]),
            .init(name: "portrait-pattern", channels: nil, amplitude: 0.2, width: 96, height: 160,
                  frameCount: 30, transform: identity, coordinatePattern: true),
            .init(name: "landscape-pattern", channels: nil, amplitude: 0.2, width: 160, height: 96,
                  frameCount: 30, transform: identity, coordinatePattern: true),
            .init(name: "portrait-rotated-pattern", channels: nil, amplitude: 0.2, width: 96, height: 160,
                  frameCount: 30, transform: [0, 1, -1, 0, 160, 0], coordinatePattern: true),
            .init(name: "portrait-pattern-15", channels: nil, amplitude: 0.2, width: 96, height: 160,
                  frameCount: 15, transform: identity, coordinatePattern: true)
        ]
        for index in specs.indices {
            let spec = specs[index]
            let fixture = try await GeneratedVideoAudioFixture(channels: spec.channels, amplitude: spec.amplitude,
                width: spec.width, height: spec.height, frameCount: spec.frameCount, transform: spec.affine,
                coordinatePattern: spec.coordinatePattern)
            defer { fixture.remove() }
            let bytes = try Data(contentsOf: fixture.videoURL)
            specs[index].byteCount = bytes.count
            specs[index].sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            try bytes.write(to: destination.appendingPathComponent("merian-video-" + spec.name + ".mp4"), options: .withoutOverwriting)
            print("Prepared \(spec.name): \(bytes.count) bytes")
        }
        let catalog = FixtureCatalog(version: 2,
            provenance: "Synthetic black or coordinate-gradient H.264 frames at 30 fps; optional 880 Hz 48000 Hz AAC tone. Authored offline with AVFoundation; no captured media or personal metadata.", fixtures: specs)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: destination.appendingPathComponent("merian-video-fixtures.json"), options: .withoutOverwriting)
    }
}
