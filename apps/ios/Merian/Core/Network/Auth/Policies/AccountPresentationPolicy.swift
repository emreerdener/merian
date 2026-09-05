import Foundation

enum AccountPresentationPolicy {
    static func isGuest(
        userID: UUID?,
        authIsAnonymous: Bool
    ) -> Bool {
        userID == nil || authIsAnonymous
    }
}
