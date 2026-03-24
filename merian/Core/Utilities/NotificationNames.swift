import Foundation

extension Notification.Name {
    /// Posted by `AppLifecycleManager` when the app transitions to the inactive state.
    static let appDidEnterInactivePhase = Notification.Name("AppDidEnterInactivePhase")
}
