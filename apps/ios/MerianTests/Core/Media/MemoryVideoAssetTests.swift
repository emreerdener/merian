import AVFoundation
import Foundation
import Testing
@testable import Merian

@MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
struct MemoryVideoAssetTests {
    @Test func rangesRespectPartialReadsEOFAndOverflow() throws {
        #expect(try MemoryVideoAsset.range(count: 12, requestedOffset: 2, currentOffset: 4, requestedLength: 6, toEnd: false) == 4..<8)
        #expect(try MemoryVideoAsset.range(count: 12, requestedOffset: 2, currentOffset: 0, requestedLength: Int.max, toEnd: true) == 2..<12)
        #expect(try MemoryVideoAsset.range(count: 12, requestedOffset: 10, currentOffset: 10, requestedLength: 5, toEnd: false) == 10..<12)
        #expect(try MemoryVideoAsset.range(count: 12, requestedOffset: 12, currentOffset: 12, requestedLength: 1, toEnd: false).isEmpty)
        for (offset, current, length) in [(Int64(-1), Int64(0), 1), (13, 0, 1), (0, 13, 1), (2, 2, Int.max), (2, 9, 1), (0, 0, -1)] {
            #expect(throws: (any Error).self) {
                try MemoryVideoAsset.range(count: 12, requestedOffset: offset, currentOffset: current, requestedLength: length, toEnd: false)
            }
        }
    }

    @Test func realMP4LoadsAfterFixtureFileRemovalAndReleasesBytes() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let bytes = try Data(contentsOf: fixture.videoURL)
        let source = try MemoryVideoAsset(bytes: bytes, validate: { true })
        try FileManager.default.removeItem(at: fixture.videoURL)
        #expect(source.asset.url.scheme == "merian-memory-video")
        #expect(source.asset.referenceRestrictions == .forbidAll)
        let playable = try await source.asset.load(.isPlayable)
        #expect(playable)
        let generator = AVAssetImageGenerator(asset: source.asset)
        let frame = try await generator.image(at: .zero)
        #expect(frame.image.width > 0 && frame.image.height > 0)
        #expect(source.retainedByteCount == bytes.count)
        source.close(); #expect(source.retainedByteCount == 0)
    }

    @Test func closedScopeCannotLoadOrRetainVideo() async throws {
        let fixture = try await VideoAudioFixture(channels: nil)
        defer { fixture.remove() }
        let bytes = try Data(contentsOf: fixture.videoURL)
        var current = true
        let source = try MemoryVideoAsset(bytes: bytes, validate: { current })
        current = false
        do { let playable = try await source.asset.load(.isPlayable); #expect(!playable) } catch { }
        #expect(source.retainedByteCount == 0)
        #expect(throws: (any Error).self) { try MemoryVideoAsset(bytes: bytes, validate: { false }) }
        #expect(throws: (any Error).self) { try MemoryVideoAsset(bytes: Data(), validate: { true }) }
    }
}
