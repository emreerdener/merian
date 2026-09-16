import Foundation

struct LegacyPurchaseIdentityProfile: Equatable {
    let email: String?
    let publicUsername: String?
    let publicAuthorName: String?
    let publicIdentitySource: String?
    let publicAvatarURL: String?
}

@MainActor
struct LegacyPurchaseIdentityProfileService {
    typealias FetchOperation = @MainActor (
        UUID
    ) async throws -> LegacyPurchaseIdentityProfile?

    private let fetchOperation: FetchOperation

    init(fetch: @escaping FetchOperation) {
        fetchOperation = fetch
    }

    func fetch(
        for userID: UUID
    ) async throws -> LegacyPurchaseIdentityProfile? {
        try await fetchOperation(userID)
    }
}
