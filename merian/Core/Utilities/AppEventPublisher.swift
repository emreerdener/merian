import Foundation
import Combine

/// Strongly-typed system events replacing legacy `NotificationCenter` broadcasts.
enum AppEvent {
    /// Dispatched when the user exceeds their scan quota and the paywall must be presented.
    case triggerPaywall
    
    /// Dispatched via push notification tap to deep-link the user directly to a newly uploaded model.
    case appDidEnterActivePhaseWithScan(scanId: String)
    
    /// Dispatched when the app enters the background / inactive phase. Modals should be dismissed.
    case appDidEnterInactivePhase
}

/// A centralized, `@MainActor`-bound event bus for system-wide internal message routing.
/// Prevents memory leaks and ensures UI-modifying events are cleanly delivered to the main thread.
@MainActor
@MainActor final class AppEventPublisher {
    static let shared = AppEventPublisher()
    
    let publisher = PassthroughSubject<AppEvent, Never>()
    
    private init() {}
    
    /// Publishes a strongly-typed event. Listeners should `.sink` onto `AppEventPublisher.shared.publisher`.
    func send(_ event: AppEvent) {
        publisher.send(event)
    }
}
