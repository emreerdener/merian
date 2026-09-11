import Combine

/// Producer-only capability. Domain services cannot subscribe through it.
@MainActor
protocol AppEventSending: AnyObject {
    func send(_ event: AppEvent)
}

/// Subscriber-only capability. Consumers cannot access the underlying subject.
@MainActor
protocol AppEventStreaming: AnyObject {
    var publisher: AnyPublisher<AppEvent, Never> { get }
}

/// A synchronous, `@MainActor`-isolated process-local invalidation bus.
/// The subject is deliberately private so callers cannot bypass actor isolation.
@MainActor
final class AppEventPublisher: AppEventSending, AppEventStreaming {
    private let subject: PassthroughSubject<AppEvent, Never>
    let publisher: AnyPublisher<AppEvent, Never>

    init() {
        let subject = PassthroughSubject<AppEvent, Never>()
        self.subject = subject
        publisher = subject.eraseToAnyPublisher()
    }

    func send(_ event: AppEvent) {
        subject.send(event)
    }
}
