import Foundation

/// Called synchronously at the user action, before any child sheet dismisses.
typealias CommunityConsentPreparation = @MainActor (String, UInt64) -> CommunityConsentTicket?

/// A one-use presentation handle, not consent or a publication operation ID.
@MainActor
final class CommunityConsentTicket {
    private var action: (() -> Void)?
    init(action: @escaping () -> Void) { self.action = action }
    func resume() {
        let action = action
        self.action = nil
        action?()
    }
    func cancel() { action = nil }
}
