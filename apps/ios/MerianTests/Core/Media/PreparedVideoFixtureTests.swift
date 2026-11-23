import AVFoundation
import CoreGraphics
import Foundation
import Testing

@Suite("Prepared video input fixtures", .timeLimit(.minutes(1)))
struct PreparedVideoFixtureTests {
    @Test func preparedVideoCatalogPreservesEveryInputVariant() async throws {
        let directory = try VideoAudioFixture.resourceDirectory()
        let entries = try VideoAudioFixture.catalog(in: directory)
        let identity = [1.0, 0, 0, 1, 0, 0]
        let rotated = [0.0, 1, -1, 0, 64, 0]
        let mirrored = [-1.0, 0, 0, 1, 96, 0]
        let expected: [String: InputFacts] = [
            "silent": .init(channels: nil, amplitude: 0.2, width: 64, frames: 30, transform: identity),
            "mono": .init(channels: 1, amplitude: 0.2, width: 64, frames: 30, transform: identity),
            "stereo": .init(channels: 2, amplitude: 0.2, width: 64, frames: 30, transform: identity),
            "quiet-mono": .init(channels: 1, amplitude: 0.01, width: 64, frames: 30, transform: identity),
            "quiet-stereo": .init(channels: 2, amplitude: 0.01, width: 64, frames: 30, transform: identity),
            "rotated-silent-3": .init(channels: nil, amplitude: 0.2, width: 96, frames: 3, transform: rotated),
            "mirrored-stereo-3": .init(channels: 2, amplitude: 0.2, width: 96, frames: 3, transform: mirrored),
            "rotated-silent-150": .init(channels: nil, amplitude: 0.2, width: 96, frames: 150, transform: rotated),
            "mirrored-stereo-150": .init(channels: 2, amplitude: 0.2, width: 96, frames: 150, transform: mirrored),
            "portrait-silent": .init(channels: nil, amplitude: 0.2, width: 96, frames: 30, transform: identity, height: 160),
            "portrait-rotated-silent": .init(channels: nil, amplitude: 0.2, width: 96, frames: 30, transform: [0, 1, -1, 0, 160, 0], height: 160),
            "portrait-pattern": .init(channels: nil, amplitude: 0.2, width: 96, frames: 30, transform: identity, height: 160, coordinatePattern: true),
            "landscape-pattern": .init(channels: nil, amplitude: 0.2, width: 160, frames: 30, transform: identity, height: 96, coordinatePattern: true),
            "portrait-rotated-pattern": .init(channels: nil, amplitude: 0.2, width: 96, frames: 30, transform: [0, 1, -1, 0, 160, 0], height: 160, coordinatePattern: true),
            "portrait-pattern-15": .init(channels: nil, amplitude: 0.2, width: 96, frames: 15, transform: identity, height: 160, coordinatePattern: true)
        ]
        #expect(Set(entries.map(\.name)) == Set(expected.keys))
        for entry in entries {
            let facts = try #require(expected[entry.name])
            #expect(entry.channels == facts.channels && entry.amplitude == facts.amplitude)
            #expect(entry.width == facts.width && entry.height == facts.height && entry.coordinatePattern == facts.coordinatePattern)
            #expect(entry.frameCount == facts.frames && entry.transform == facts.transform)
            let transform = CGAffineTransform(a: entry.transform[0], b: entry.transform[1],
                c: entry.transform[2], d: entry.transform[3], tx: entry.transform[4], ty: entry.transform[5])
            let fixture = try await VideoAudioFixture(channels: entry.channels, amplitude: entry.amplitude,
                width: entry.width, height: entry.height, frameCount: entry.frameCount, transform: transform, coordinatePattern: entry.coordinatePattern)
            defer { fixture.remove() }
            #expect(try Data(contentsOf: fixture.videoURL) == VideoAudioFixture.validatedBytes(entry, in: directory))
            let asset = AVURLAsset(url: fixture.videoURL)
            let videos = try await asset.loadTracks(withMediaType: .video)
            let audios = try await asset.loadTracks(withMediaType: .audio)
            #expect(videos.count == 1 && audios.count == (entry.channels == nil ? 0 : 1))
            #expect(abs(try await asset.load(.duration).seconds - Double(entry.frameCount) / 30) < 1.0 / 600)
            let video = try #require(videos.first)
            #expect(try await video.load(.preferredTransform) == transform)
            let description = try #require(try await video.load(.formatDescriptions).first)
            #expect(CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_H264)
            let size = CMVideoFormatDescriptionGetDimensions(description)
            #expect(size.width == entry.width && size.height == entry.height)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            reader.add(output)
            #expect(reader.startReading())
            var frames = 0
            while let sample = output.copyNextSampleBuffer() { frames += CMSampleBufferGetNumSamples(sample) }
            #expect(reader.status == .completed)
            #expect(frames == entry.frameCount, "Frame count for \(entry.name)")
            try await Self.validateDecodedPattern(asset: asset, entry: entry)
            if let audio = audios.first {
                let audioDescription = try #require(try await audio.load(.formatDescriptions).first)
                #expect(CMFormatDescriptionGetMediaSubType(audioDescription) == kAudioFormatMPEG4AAC)
                let format = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription)?.pointee)
                #expect(format.mSampleRate == 48_000 && Int(format.mChannelsPerFrame) == entry.channels)
                let peak = try Self.audioPeak(asset: asset, track: audio)
                if entry.amplitude == 0.01 {
                    #expect(peak > 0.005 && peak < 0.03, "Quiet input for \(entry.name)")
                } else {
                    #expect(peak > 0.05 && peak < 0.5, "Audible input for \(entry.name)")
                }
            }
        }
    }

    @Test func concurrentPreparedFixturesKeepIndependentCopiesAndCancellation() async throws {
        let fixtures = try await withThrowingTaskGroup(of: VideoAudioFixture.self) { group in
            for channels in [nil, 1, 2, nil, 1, 2] as [Int?] {
                group.addTask { try await VideoAudioFixture(channels: channels) }
            }
            var fixtures: [VideoAudioFixture] = []
            do {
                for try await fixture in group { fixtures.append(fixture) }
            } catch {
                group.cancelAll()
                while let result = await group.nextResult() {
                    if case .success(let fixture) = result { fixture.remove() }
                }
                for fixture in fixtures { fixture.remove() }
                throw error
            }
            return fixtures
        }
        defer { for fixture in fixtures { fixture.remove() } }
        #expect(Set(fixtures.map(\.root)).count == 6)
        for fixture in fixtures {
            let videos = try await AVURLAsset(url: fixture.videoURL).loadTracks(withMediaType: .video)
            #expect(videos.count == 1)
            #expect(try fixture.outputFiles().isEmpty)
        }
        let first = try #require(fixtures.first)
        try Data([0]).write(to: first.videoURL)
        first.remove()
        #expect(!FileManager.default.fileExists(atPath: first.root.path))
        for fixture in fixtures.dropFirst() {
            #expect(try Data(contentsOf: fixture.videoURL).count > 1)
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VideoAudioFixture(channels: 1)
        }
        do {
            let unexpected = try await cancelled.value
            unexpected.remove()
            Issue.record("Cancelled fixture creation must not complete")
        } catch is CancellationError { }
        let afterCancellation = try await VideoAudioFixture(channels: 2)
        defer { afterCancellation.remove() }
        #expect(FileManager.default.fileExists(atPath: afterCancellation.videoURL.path))
    }

    @Test(arguments: ["hash", "size", "missing", "symlink", "duplicate-name", "version", "unsupported", "cancelled"])
    func preparedFixturesRejectInvalidInputs(_ boundary: String) async throws {
        if boundary == "unsupported" {
            do {
                let unexpected = try await VideoAudioFixture(channels: 3)
                unexpected.remove()
                Issue.record("Unsupported fixture configuration must fail")
            } catch { #expect(error as? VideoAudioFixture.FixtureError == .unsupportedConfiguration) }
            return
        }
        if boundary == "cancelled" {
            let work = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await VideoAudioFixture(channels: nil)
            }
            do {
                let unexpected = try await work.value
                unexpected.remove()
                Issue.record("Pre-cancelled fixture construction must fail")
            } catch { #expect(error is CancellationError) }
            return
        }
        let source = try VideoAudioFixture.resourceDirectory()
        let entry = try #require(try VideoAudioFixture.catalog(in: source).first { $0.name == "mono" })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("merian-video-" + entry.name + ".mp4")
        if boundary == "duplicate-name" || boundary == "version" {
            var catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                source.appendingPathComponent("merian-video-fixtures.json"))) as? [String: Any])
            if boundary == "version" { catalog["version"] = 999 } else {
                var entries = try #require(catalog["fixtures"] as? [[String: Any]])
                entries[1]["name"] = entries[0]["name"]
                catalog["fixtures"] = entries
            }
            try JSONSerialization.data(withJSONObject: catalog).write(to: root.appendingPathComponent("merian-video-fixtures.json"))
            #expect(throws: VideoAudioFixture.FixtureError.invalidCatalog) {
                try VideoAudioFixture.catalog(in: root)
            }
        } else if boundary == "missing" {
            #expect(throws: (any Error).self) { try VideoAudioFixture.validatedBytes(entry, in: root) }
        } else {
            if boundary == "symlink" {
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL:
                    source.appendingPathComponent("merian-video-" + entry.name + ".mp4"))
            } else {
                var bytes = try VideoAudioFixture.validatedBytes(entry, in: source)
                if boundary == "size" { bytes.append(0) } else { bytes[0] ^= 1 }
                try bytes.write(to: file)
            }
            #expect(throws: VideoAudioFixture.FixtureError.invalidMedia) {
                try VideoAudioFixture.validatedBytes(entry, in: root)
            }
        }
    }

    private static func validateDecodedPattern(asset: AVAsset, entry: VideoAudioFixture.Entry) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = false
        let image = try await generator.image(at: .zero).image
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 8, height: 8,
                bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        func channel(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(bytes[(y * 8 + x) * 4 + c]) }
        if entry.coordinatePattern {
            // Independent spatial evidence: a uniform clip cannot qualify merely
            // because two downstream derivatives agree with each other.
            #expect(abs(channel(6, 3, 0) - channel(1, 3, 0)) > 120, "Red x-gradient: \(entry.name)")
            #expect(abs(channel(3, 6, 1) - channel(3, 1, 1)) > 120, "Green y-gradient: \(entry.name)")
            #expect(abs(channel(3, 6, 0) - channel(3, 1, 0)) < 20, "Red y-invariance: \(entry.name)")
            #expect(abs(channel(6, 3, 1) - channel(1, 3, 1)) < 20, "Green x-invariance: \(entry.name)")
            #expect((40...90).contains(channel(3, 3, 2)), "Fixed blue component: \(entry.name)")
        } else {
            #expect(bytes.enumerated().filter { $0.offset % 4 < 3 }.allSatisfy { $0.element < 10 },
                "Black input: \(entry.name)")
        }
    }

    private struct InputFacts {
        let channels: Int?
        let amplitude: Double
        let width: Int
        let frames: Int
        let transform: [Double]
        var height: Int = 64
        var coordinatePattern: Bool = false
    }

    private static func audioPeak(asset: AVAsset, track: AVAssetTrack) throws -> Float {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        try #require(reader.startReading())
        var peak: Float = 0
        while let sample = output.copyNextSampleBuffer() {
            let block = try #require(CMSampleBufferGetDataBuffer(sample))
            let size = CMBlockBufferGetDataLength(block)
            try #require(size > 0 && size <= 1_048_576 && size.isMultiple(of: MemoryLayout<Float>.size))
            var values = [Float](repeating: 0, count: size / MemoryLayout<Float>.size)
            let status = try values.withUnsafeMutableBytes {
                let destination = try #require($0.baseAddress)
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: destination)
            }
            try #require(status == kCMBlockBufferNoErr)
            for value in values { peak = max(peak, abs(value)) }
        }
        #expect(reader.status == .completed)
        return peak
    }

}
