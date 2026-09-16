import Foundation
import Testing
@testable import Merian

@Suite("Legacy Purchase Identity Profile Service")
@MainActor
struct LegacyPurchaseIdentityProfileServiceTests {
    @Test func injectedFetchPreservesTheExactAccountAndProjection() async throws {
        let userID = UUID()
        let expected = LegacyPurchaseIdentityProfile(
            email: "member@example.test",
            publicUsername: "river_wren",
            publicAuthorName: "River W.",
            publicIdentitySource: "derived_name",
            publicAvatarURL: "https://example.test/avatar.jpg"
        )
        var receivedUserID: UUID?
        let service = LegacyPurchaseIdentityProfileService { userID in
            receivedUserID = userID
            return expected
        }

        let result = try await service.fetch(for: userID)

        #expect(receivedUserID == userID)
        #expect(result == expected)
    }
}
