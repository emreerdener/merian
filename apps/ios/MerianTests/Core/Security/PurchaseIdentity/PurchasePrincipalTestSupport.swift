import Foundation
@testable import Merian

final class PurchasePrincipalSecureStoreSpy: PurchasePrincipalSecureStore {
    var values: [String: Data] = [:]
    var readError: Error?
    var acceptsWrites = true
    var discardsWrites = false
    private(set) var writes: [
        (key: String, accessibility: KeychainManager.Accessibility)
    ] = []

    func dataOrThrow(forKey key: String) throws -> Data? {
        if let readError { throw readError }
        return values[key]
    }

    func set(
        _ data: Data,
        forKey key: String,
        accessibility: KeychainManager.Accessibility
    ) -> Bool {
        writes.append((key, accessibility))
        guard acceptsWrites else { return false }
        if !discardsWrites {
            values[key] = data
        }
        return true
    }
}

enum PurchasePrincipalTestError: Error, Equatable {
    case locked
    case notFound
    case transport
}
