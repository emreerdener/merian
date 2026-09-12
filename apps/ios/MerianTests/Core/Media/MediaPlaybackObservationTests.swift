import AVFoundation
@testable import Merian
import Testing

@MainActor
@Suite("Media Playback Observation")
struct MediaPlaybackObservationTests {
    @Test func ignoresReplacedAndDetachedPlayerCallbacks() throws {
        let observation = MediaPlaybackObservation()
        let oldURL = try #require(URL(string: "https://example.com/old.mp4"))
        let newURL = try #require(URL(string: "https://example.com/new.mp4"))
        let oldItem = AVPlayerItem(url: oldURL)
        let oldPlayer = AVPlayer(playerItem: oldItem)
        let newItem = AVPlayerItem(url: newURL)
        let newPlayer = AVPlayer(playerItem: newItem)

        observation.observe(oldPlayer)
        observation.observe(newPlayer)
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: oldItem
        )
        #expect(observation.eventSequence == 0)

        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: newItem
        )
        #expect(observation.eventSequence == 1)
        #expect(observation.lastEvent == .didReachEnd)

        observation.detach()
        NotificationCenter.default.post(
            name: .AVPlayerItemDidPlayToEndTime,
            object: newItem
        )
        #expect(observation.eventSequence == 1)
    }
}
