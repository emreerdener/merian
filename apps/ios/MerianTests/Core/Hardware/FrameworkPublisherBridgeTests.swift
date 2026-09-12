import Combine
import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Framework Publisher Bridge")
struct FrameworkPublisherBridgeTests {
    @Test func preservesOrderedMainActorDelivery() async {
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
        while deliveries.count < 3, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(deliveries == [1, 3, 2])
    }
}
