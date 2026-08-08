import AVFoundation
import Combine
import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Event Delivery")
struct EventDeliveryTests {
    @Test func appEventsDeliverSynchronouslyAndPreserveReentrancy() {
        let eventPublisher = AppEventPublisher()
        var deliveries: [String] = []
        let cancellable = eventPublisher.publisher.sink { event in
            switch event {
            case .scanLibraryChanged:
                deliveries.append("library")
                eventPublisher.send(.manualAppleRevocationNoticeRequired)
            case .manualAppleRevocationNoticeRequired:
                deliveries.append("revocation")
            default:
                break
            }
        }

        eventPublisher.send(.scanLibraryChanged)

        #expect(deliveries == ["library", "revocation"])
        cancellable.cancel()
        eventPublisher.send(.scanLibraryChanged)
        #expect(deliveries == ["library", "revocation"])
    }

    @Test func frameworkPublisherBridgePreservesOrderOnMainActor() async {
        let subject = PassthroughSubject<Int, Never>()
        var deliveries: [Int] = []
        var cancellable: AnyCancellable?
        cancellable = subject.sinkOnMainActor { value in
            #expect(Thread.isMainThread)
            deliveries.append(value)
            if value == 1 {
                subject.send(2)
            }
        }
        defer { cancellable?.cancel() }

        subject.send(1)
        subject.send(3)

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while deliveries.count < 3 && ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(deliveries == [1, 3, 2])
    }

    @Test func mediaObserverIgnoresReplacedAndDetachedPlayerCallbacks() {
        let observation = MediaPlaybackObservation()
        let oldItem = AVPlayerItem(url: URL(string: "https://example.com/old.mp4")!)
        let oldPlayer = AVPlayer(playerItem: oldItem)
        let newItem = AVPlayerItem(url: URL(string: "https://example.com/new.mp4")!)
        let newPlayer = AVPlayer(playerItem: newItem)

        observation.observe(oldPlayer)
        observation.observe(newPlayer)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        #expect(observation.eventSequence == 0)

        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: newItem)
        #expect(observation.eventSequence == 1)
        #expect(observation.lastEvent == .didReachEnd)

        observation.detach()
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: newItem)
        #expect(observation.eventSequence == 1)
    }
}
