import Combine
import Foundation

/// Strongly-typed system events replacing legacy `NotificationCenter` broadcasts.
enum AppEvent {
    /// Dispatched when the user exceeds their scan quota and the paywall must be presented.
    case triggerPaywall
    
    /// Dispatched via push notification tap to deep-link the user directly to a newly uploaded model.
    case appDidEnterActivePhaseWithScan(scanId: String)
    
    /// Dispatched when the app enters the background phase. Modals should be dismissed.
    /// Fires on background (not inactive) so that system overlays — such as the iOS limited
    /// photo library access prompt — do not inadvertently close the insight sheet.
    case appDidEnterBackgroundPhase
    
    /// Dispatched by Siri/OS intents to immediately jump the user to the lens viewfinder.
    case requestIdentifyNatureIntent
    
    /// Dispatched by Siri/OS intents to immediately open the historical scans insight page.
    case requestRecallLastFindIntent
    
    /// Dispatched to seamlessly jump the user from an ambiguous Insight Sheet back to the Camera, 
    /// carrying the `LocalScanRecord` context forward into a supplementary multi-image generation sequence.
    case triggerRefinement(record: LocalScanRecord)
}

/// A centralized, `@MainActor`-bound event bus for system-wide internal message routing.
/// Prevents memory leaks and ensures UI-modifying events are cleanly delivered to the main thread.
@MainActor
final class AppEventPublisher {
    static let shared = AppEventPublisher()
    
    let publisher = PassthroughSubject<AppEvent, Never>()
    
    private init() {}
    
    /// Publishes a strongly-typed event. Listeners should `.sink` onto `AppEventPublisher.shared.publisher`.
    func send(_ event: AppEvent) {
        publisher.send(event)
    }
}
