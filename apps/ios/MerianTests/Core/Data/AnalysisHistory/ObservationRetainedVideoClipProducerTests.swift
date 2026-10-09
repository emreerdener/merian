import AVFoundation
import Foundation
@testable import Merian
import Testing

@Suite(.serialized)
struct ObservationRetainedVideoTests {
    @Test(arguments: [false, true])
    func canonicalClipRetainsExplicitTracksAndBoundedTopology(audio: Bool) async throws {
        let fixture = try await VideoAudioFixture(channels: audio ? 2 : nil)
        defer { fixture.remove() }
        let original = try Data(contentsOf: fixture.videoURL)
        let lease = try await ObservationRetainedVideoClipProducer().prepare(
            source: fixture.videoURL, directory: fixture.outputDirectory
        )
        #expect(lease.url != fixture.videoURL)
        #expect(try Data(contentsOf: fixture.videoURL) == original)
        let entries = try FileManager.default.contentsOfDirectory(atPath: lease.url.deletingLastPathComponent().path)
        #expect(entries == ["retained.mp4"])
        let bytes = try Data(contentsOf: lease.url)
        #expect(!bytes.isEmpty && bytes.count <= ScanMediaPayloadPolicy.maxSavedVideoBytes)
        let boxes = try topLevelBoxes(bytes)
        #expect(boxes.filter { $0 == "ftyp" }.count == 1)
        #expect(boxes.filter { $0 == "moov" }.count == 1)
        #expect(boxes.filter { $0 == "mdat" }.count == 1)
        #expect(boxes.allSatisfy { ["ftyp", "moov", "mdat", "free", "wide"].contains($0) })
        let asset = AVURLAsset(url: lease.url)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        #expect(videos.count == 1)
        #expect(audios.count == (audio ? 1 : 0))
        let video = try #require(videos.first)
        let descriptions = try await video.load(.formatDescriptions)
        let description = try #require(descriptions.first)
        #expect(CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_H264)
        let atoms = try #require(CMFormatDescriptionGetExtension(
            description, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
        ) as? [String: Data])
        let configuration = try #require(atoms["avcC"])
        #expect(configuration.count >= 4)
        if configuration.count >= 4 { #expect(configuration[1] == 77) } // H.264 Main profile_idc.
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        #expect(dimensions.width == 64 && dimensions.height == 64)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 1) < 0.05)
        let metadata = try await asset.load(.metadata)
        #expect(metadata.isEmpty)
        if let track = audios.first {
            let descriptions = try await track.load(.formatDescriptions)
            let description = try #require(descriptions.first)
            #expect(CMFormatDescriptionGetMediaSubType(description) == kAudioFormatMPEG4AAC)
            let format = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee)
            #expect(format.mSampleRate == 44_100 && format.mChannelsPerFrame == 1)
        }
        // Caller must explicitly accept a successful result; source is never deleted.
        #expect(try await lease.relinquishOwnership() == lease.url)
    }

    @Test
    func droppingSuccessfulLeaseRemovesOnlyItsOutput() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let output = try await makeUnacceptedClip(fixture)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(atPath: output.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    private func makeUnacceptedClip(_ fixture: VideoAudioFixture) async throws -> URL {
        let lease = try await ObservationRetainedVideoClipProducer().prepare(
            source: fixture.videoURL, directory: fixture.outputDirectory
        )
        #expect(FileManager.default.fileExists(atPath: lease.url.path))
        return lease.url
    }

    @Test
    func cancellationAfterAppendDrainsBeforeProducerReuse() async throws {
        let fixture = try await VideoAudioFixture(channels: 2)
        defer { fixture.remove() }
        let sibling = fixture.outputDirectory.appendingPathComponent("sibling.txt")
        try Data([42]).write(to: sibling)
        let checkpoint = RetainedVideoValidationCheckpoint()
        let producer = ObservationRetainedVideoClipProducer {
            if await checkpoint.enterFirst() { try await Task.sleep(for: .seconds(30)) }
        }
        let task = Task { try await producer.prepare(source: fixture.videoURL, directory: fixture.outputDirectory) }
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await checkpoint.entered), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let entered = await checkpoint.entered
        #expect(entered)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled encoding unexpectedly succeeded")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        let remainingFiles = try fixture.outputFiles().map(\.lastPathComponent)
        #expect(remainingFiles == ["sibling.txt"], "Unexpected synthetic output entries: \(remainingFiles)")
        #expect(try Data(contentsOf: sibling) == Data([42]))
        let retry = try await producer.prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        #expect(FileManager.default.fileExists(atPath: retry.url.path))
    }

    @Test
    func cancelledPreparationDoesNotCreateOrDeleteSourceFiles() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let producer = ObservationRetainedVideoClipProducer()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await producer.prepare(source: fixture.videoURL, directory: fixture.outputDirectory)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled preparation unexpectedly succeeded")
        } catch is CancellationError {} catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        let remainingFiles = try fixture.outputFiles().map(\.lastPathComponent)
        #expect(remainingFiles.isEmpty, "Unexpected synthetic output entries: \(remainingFiles)")
        #expect(FileManager.default.fileExists(atPath: fixture.videoURL.path))
    }

    @Test
    func invalidInputNeverBecomesRetainedOutput() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let bad = fixture.root.appendingPathComponent("invalid.mp4")
        try Data([0, 1, 2]).write(to: bad)
        do {
            _ = try await ObservationRetainedVideoClipProducer().prepare(source: bad, directory: fixture.outputDirectory)
            Issue.record("Malformed video unexpectedly accepted")
        } catch {}
        let remainingFiles = try fixture.outputFiles().map(\.lastPathComponent)
        #expect(remainingFiles.isEmpty, "Unexpected synthetic output entries: \(remainingFiles)")
        #expect(try Data(contentsOf: bad) == Data([0, 1, 2]))
    }

    @Test
    func onlyBoundedOrthogonalTransformsAreSupported() {
        #expect(ObservationRetainedVideoClipProducer.supportsTransform(.identity))
        #expect(ObservationRetainedVideoClipProducer.supportsTransform(
            CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        ))
        for transform in [
            CGAffineTransform(scaleX: 2, y: 1),
            CGAffineTransform(a: 1, b: 1, c: 0, d: 1, tx: 0, ty: 0),
            CGAffineTransform(translationX: 4096, y: 0),
            CGAffineTransform(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        ] {
            #expect(!ObservationRetainedVideoClipProducer.supportsTransform(transform))
        }
    }

    /// Test-only topology evidence, not a production MP4 security validator.
    private func topLevelBoxes(_ data: Data) throws -> [String] {
        let bytes = [UInt8](data)
        var offset = 0
        var result: [String] = []
        while offset < bytes.count {
            try #require(result.count < 32 && bytes.count - offset >= 8)
            let short = bytes[offset..<offset + 4].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let type = try #require(String(bytes: bytes[offset + 4..<offset + 8], encoding: .ascii))
            var length = short
            if short == 1 {
                try #require(bytes.count - offset >= 16)
                length = bytes[offset + 8..<offset + 16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            }
            try #require(length >= (short == 1 ? 16 : 8) && length <= UInt64(bytes.count - offset))
            result.append(type)
            offset += Int(length)
        }
        return result
    }
}

private actor RetainedVideoValidationCheckpoint {
    private(set) var entered = false

    func enterFirst() -> Bool {
        guard !entered else { return false }
        entered = true
        return true
    }
}
