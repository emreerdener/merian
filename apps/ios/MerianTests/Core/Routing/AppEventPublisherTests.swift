import Combine
@testable import Merian
import Testing

@MainActor
@Suite("App event publisher")
struct AppEventPublisherTests {
    @Test func eventsDeliverSynchronouslyAndPreserveReentrancy() {
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
}
