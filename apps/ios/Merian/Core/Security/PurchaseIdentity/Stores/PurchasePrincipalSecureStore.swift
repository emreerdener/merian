import Foundation

protocol PurchasePrincipalSecureStore: AnyObject {
    func dataOrThrow(forKey key: String) throws -> Data?

    @discardableResult
    func set(
        _ data: Data,
        forKey key: String,
        accessibility: KeychainManager.Accessibility
    ) -> Bool
}

extension KeychainManager: PurchasePrincipalSecureStore {}
